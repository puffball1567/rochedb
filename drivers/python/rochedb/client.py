from __future__ import annotations

from dataclasses import dataclass
import socket
import struct
from typing import Iterable, Optional


class RocheError(Exception):
    pass


@dataclass(frozen=True)
class RocheId:
    parent: int
    epoch: int
    seq: int
    t_write: float
    period: float
    head: float

    @classmethod
    def parse(cls, text: str) -> "RocheId":
        parts = text.split(":")
        if len(parts) != 6:
            raise ValueError("RocheId text must have 6 ':'-separated fields")
        return cls(
            parent=int(parts[0]),
            epoch=int(parts[1]),
            seq=int(parts[2]),
            t_write=float(parts[3]),
            period=float(parts[4]),
            head=float(parts[5]),
        )

    def __str__(self) -> str:
        return (
            f"{self.parent}:{self.epoch}:{self.seq}:"
            f"{self.t_write}:{self.period}:{self.head}"
        )


def _parse_peers(peers: str | Iterable[str]) -> list[tuple[str, int]]:
    values = peers.split(",") if isinstance(peers, str) else list(peers)
    parsed: list[tuple[str, int]] = []
    for value in values:
        host, sep, port = value.rpartition(":")
        if not sep or not host or not port:
            raise ValueError(f"invalid peer '{value}', expected host:port")
        parsed.append((host, int(port)))
    if not parsed:
        raise ValueError("peers must not be empty")
    return parsed


def _vec_bytes(vector: Optional[Iterable[float]]) -> bytes:
    if vector is None:
        return b""
    values = [float(v) for v in vector]
    if not values:
        return b""
    return struct.pack("<" + "f" * len(values), *values)


class RocheClient:
    def __init__(self, peers: str | Iterable[str], timeout: float = 10.0):
        self.peers = _parse_peers(peers)
        self.timeout = timeout
        self._socks: dict[int, socket.socket] = {}

    @classmethod
    def connect(cls, peers: str | Iterable[str], timeout: float = 10.0) -> "RocheClient":
        return cls(peers, timeout=timeout)

    def close(self) -> None:
        for sock in self._socks.values():
            try:
                sock.close()
            except OSError:
                pass
        self._socks.clear()

    def __enter__(self) -> "RocheClient":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def put(
        self,
        ring: str,
        payload: bytes | str,
        vector: Optional[Iterable[float]] = None,
        node: int = 0,
    ) -> RocheId:
        ring_b = ring.encode("utf-8")
        payload_b = payload.encode("utf-8") if isinstance(payload, str) else bytes(payload)
        vec_b = _vec_bytes(vector)
        vec_dim = len(vec_b) // 4
        header = f"PUTR {len(ring_b)} {len(payload_b)} {vec_dim}"
        parts = self._rpc(node, header, ring_b + payload_b + vec_b)
        if not parts or parts[0] != "ID" or len(parts) != 7:
            raise RocheError("PUTR failed: " + " ".join(parts))
        return RocheId(
            parent=int(parts[1]),
            epoch=int(parts[2]),
            seq=int(parts[3]),
            t_write=float(parts[4]),
            period=float(parts[5]),
            head=float(parts[6]),
        )

    def get(self, doc_id: RocheId, node: Optional[int] = None) -> Optional[bytes]:
        return self._read_with_fallback("GETID", doc_id, b"", node=node)

    def query(
        self, doc_id: RocheId, selection: str, node: Optional[int] = None
    ) -> Optional[bytes]:
        selection_b = selection.encode("utf-8")
        return self._read_with_fallback("QRYID", doc_id, selection_b, node=node)

    def health(self, node: int = 0) -> str:
        parts = self._rpc(node, "HEALTH")
        if not parts or parts[0] != "OK":
            raise RocheError("HEALTH failed: " + " ".join(parts))
        return " ".join(parts[1:])

    def _read_id(self, op: str, doc_id: RocheId, selection: bytes, node: int) -> Optional[bytes]:
        header = (
            f"{op} {doc_id.parent} {doc_id.epoch} {doc_id.seq} "
            f"{doc_id.t_write} {doc_id.period} {doc_id.head}"
        )
        if op == "QRYID":
            header += f" {len(selection)}"
        parts = self._rpc(node, header, selection)
        if not parts:
            raise RocheError(f"{op} returned an empty response")
        if parts[0] == "MISS":
            return None
        if parts[0] == "ERR":
            raise RocheError(" ".join(parts[1:]))
        if parts[0] == "FWD":
            if len(parts) != 7:
                raise RocheError("invalid FWD response: " + " ".join(parts))
            fwd = RocheId(
                parent=int(parts[1]),
                epoch=int(parts[2]),
                seq=int(parts[3]),
                t_write=float(parts[4]),
                period=float(parts[5]),
                head=float(parts[6]),
            )
            return self._read_id(op, fwd, selection, node=node)
        if parts[0] != "VAL" or len(parts) != 3:
            raise RocheError(f"{op} failed: " + " ".join(parts))
        return self._read_exact(self._socket_for(node), int(parts[2]))

    def _read_with_fallback(
        self, op: str, doc_id: RocheId, selection: bytes, node: Optional[int]
    ) -> Optional[bytes]:
        if node is not None:
            return self._read_id(op, doc_id, selection, node=node)
        first = self._read_id(op, doc_id, selection, node=0)
        if first is not None or len(self.peers) == 1:
            return first
        for peer_node in range(1, len(self.peers)):
            value = self._read_id(op, doc_id, selection, node=peer_node)
            if value is not None:
                return value
        return None

    def _rpc(self, node: int, header: str, payload: bytes = b"") -> list[str]:
        last_error: Optional[BaseException] = None
        for attempt in range(2):
            try:
                sock = self._socket_for(node)
                sock.sendall(header.encode("utf-8") + b"\n" + payload)
                return self._read_header(sock)
            except OSError as err:
                last_error = err
                self._drop_socket(node)
                if attempt == 1:
                    raise RocheError(str(err)) from err
        raise RocheError(str(last_error))

    def _socket_for(self, node: int) -> socket.socket:
        if node < 0 or node >= len(self.peers):
            raise IndexError(f"node out of range: {node}")
        sock = self._socks.get(node)
        if sock is not None:
            return sock
        host, port = self.peers[node]
        sock = socket.create_connection((host, port), timeout=self.timeout)
        sock.settimeout(self.timeout)
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        self._socks[node] = sock
        return sock

    def _drop_socket(self, node: int) -> None:
        sock = self._socks.pop(node, None)
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass

    def _read_header(self, sock: socket.socket) -> list[str]:
        chunks: list[bytes] = []
        while True:
            b = sock.recv(1)
            if not b:
                raise RocheError("connection closed")
            if b == b"\n":
                return b"".join(chunks).decode("utf-8").split(" ")
            chunks.append(b)

    def _read_exact(self, sock: socket.socket, n: int) -> bytes:
        chunks: list[bytes] = []
        remaining = n
        while remaining > 0:
            chunk = sock.recv(remaining)
            if not chunk:
                raise RocheError("connection closed")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

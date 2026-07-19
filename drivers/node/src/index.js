import net from "node:net";

class OrbeliasError extends Error {
  constructor(message) {
    super(message);
    this.name = "OrbeliasError";
  }
}

class OrbeliasId {
  constructor(parent, epoch, seq, tWrite, period, head) {
    this.parent = BigInt(parent);
    this.epoch = Number(epoch);
    this.seq = Number(seq);
    this.tWrite = Number(tWrite);
    this.period = Number(period);
    this.head = Number(head);
    Object.freeze(this);
  }

  static parse(text) {
    const parts = String(text).split(":");
    if (parts.length !== 6) {
      throw new OrbeliasError("OrbeliasId text must have 6 ':'-separated fields");
    }
    return new OrbeliasId(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  toString() {
    return [
      this.parent.toString(),
      this.epoch,
      this.seq,
      this.tWrite,
      this.period,
      this.head,
    ].join(":");
  }
}

function parsePeers(peers) {
  const values = Array.isArray(peers) ? peers : String(peers).split(",");
  const parsed = values.map((value) => {
    const text = String(value);
    const idx = text.lastIndexOf(":");
    if (idx <= 0 || idx === text.length - 1) {
      throw new OrbeliasError(`invalid peer '${text}', expected host:port`);
    }
    return { host: text.slice(0, idx), port: Number(text.slice(idx + 1)) };
  });
  if (parsed.length === 0) {
    throw new OrbeliasError("peers must not be empty");
  }
  return parsed;
}

function payloadBuffer(payload) {
  return Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload), "utf8");
}

function vectorBuffer(vector) {
  if (!vector || vector.length === 0) {
    return Buffer.alloc(0);
  }
  const buf = Buffer.alloc(vector.length * 4);
  for (let i = 0; i < vector.length; i += 1) {
    buf.writeFloatLE(Number(vector[i]), i * 4);
  }
  return buf;
}

class OrbeliasConnection {
  constructor(peer, timeoutMs) {
    this.peer = peer;
    this.timeoutMs = timeoutMs;
    this.socket = null;
    this.buffer = Buffer.alloc(0);
    this.waiter = null;
    this.queue = Promise.resolve();
  }

  async close() {
    if (!this.socket) {
      return;
    }
    const sock = this.socket;
    this.socket = null;
    sock.destroy();
  }

  async rpc(header, payload = Buffer.alloc(0)) {
    const run = async () => {
      let lastError = null;
      for (let attempt = 0; attempt < 2; attempt += 1) {
        try {
          const sock = await this.socketFor();
          sock.write(Buffer.concat([Buffer.from(header + "\n", "utf8"), payload]));
          return await this.readHeader();
        } catch (err) {
          lastError = err;
          await this.close();
          if (attempt === 1) {
            throw err;
          }
        }
      }
      throw lastError;
    };
    this.queue = this.queue.then(run, run);
    return this.queue;
  }

  async socketFor() {
    if (this.socket) {
      return this.socket;
    }
    this.buffer = Buffer.alloc(0);
    this.socket = await new Promise((resolve, reject) => {
      const sock = net.createConnection(this.peer);
      let done = false;
      const finish = (err) => {
        if (done) {
          return;
        }
        done = true;
        sock.removeListener("connect", onConnect);
        sock.removeListener("error", onError);
        if (err) {
          sock.destroy();
          reject(err);
        } else {
          resolve(sock);
        }
      };
      const onConnect = () => finish(null);
      const onError = (err) => finish(err);
      sock.once("connect", onConnect);
      sock.once("error", onError);
      sock.setTimeout(this.timeoutMs, () => finish(new OrbeliasError("connection timeout")));
    });
    this.socket.setNoDelay(true);
    this.socket.setTimeout(this.timeoutMs);
    this.socket.on("data", (chunk) => {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      this.notify();
    });
    this.socket.on("close", () => this.notify());
    this.socket.on("error", () => this.notify());
    return this.socket;
  }

  notify() {
    if (this.waiter) {
      const resolve = this.waiter;
      this.waiter = null;
      resolve();
    }
  }

  async waitForData() {
    if (this.buffer.length > 0) {
      return;
    }
    await new Promise((resolve) => {
      this.waiter = resolve;
    });
  }

  async readHeader() {
    while (true) {
      const idx = this.buffer.indexOf(0x0a);
      if (idx >= 0) {
        const line = this.buffer.subarray(0, idx).toString("utf8");
        this.buffer = this.buffer.subarray(idx + 1);
        return line.split(" ");
      }
      await this.waitForData();
      if (!this.socket || this.socket.destroyed) {
        throw new OrbeliasError("connection closed");
      }
    }
  }

  async readExact(n) {
    while (this.buffer.length < n) {
      await this.waitForData();
      if (!this.socket || this.socket.destroyed) {
        throw new OrbeliasError("connection closed");
      }
    }
    const out = this.buffer.subarray(0, n);
    this.buffer = this.buffer.subarray(n);
    return out;
  }
}

class OrbeliasClient {
  constructor(peers, options = {}) {
    this.peers = parsePeers(peers);
    this.timeoutMs = options.timeoutMs ?? options.timeout ?? 10_000;
    this.connections = new Map();
  }

  static connect(peers, options = {}) {
    return new OrbeliasClient(peers, options);
  }

  async close() {
    await Promise.all([...this.connections.values()].map((conn) => conn.close()));
    this.connections.clear();
  }

  async put(ring, payload, options = {}) {
    const node = options.node ?? 0;
    const ringBuf = Buffer.from(String(ring), "utf8");
    const payloadBuf = payloadBuffer(payload);
    const vecBuf = vectorBuffer(options.vector);
    const vecDim = vecBuf.length / 4;
    const parts = await this.rpc(
      node,
      `PUTR ${ringBuf.length} ${payloadBuf.length} ${vecDim}`,
      Buffer.concat([ringBuf, payloadBuf, vecBuf])
    );
    if (parts[0] !== "ID" || parts.length !== 7) {
      throw new OrbeliasError("PUTR failed: " + parts.join(" "));
    }
    return new OrbeliasId(parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]);
  }

  async get(id, options = {}) {
    return this.readWithFallback("GETID", id, Buffer.alloc(0), options);
  }

  async query(id, selection, options = {}) {
    return this.readWithFallback("QRYID", id, Buffer.from(String(selection), "utf8"), options);
  }

  async health(node = 0) {
    const parts = await this.rpc(node, "HEALTH");
    if (parts[0] !== "OK") {
      throw new OrbeliasError("HEALTH failed: " + parts.join(" "));
    }
    return parts.slice(1).join(" ");
  }

  async readId(op, id, selection, node) {
    let header = `${op} ${id.parent.toString()} ${id.epoch} ${id.seq} ${id.tWrite} ${id.period} ${id.head}`;
    if (op === "QRYID") {
      header += ` ${selection.length}`;
    }
    const parts = await this.rpc(node, header, selection);
    if (parts[0] === "MISS") {
      return null;
    }
    if (parts[0] === "ERR") {
      throw new OrbeliasError(parts.slice(1).join(" "));
    }
    if (parts[0] === "FWD") {
      if (parts.length !== 7) {
        throw new OrbeliasError("invalid FWD response: " + parts.join(" "));
      }
      return this.readId(
        op,
        new OrbeliasId(parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]),
        selection,
        node
      );
    }
    if (parts[0] !== "VAL" || parts.length !== 3) {
      throw new OrbeliasError(`${op} failed: ${parts.join(" ")}`);
    }
    return this.connectionFor(node).readExact(Number(parts[2]));
  }

  async readWithFallback(op, id, selection, options) {
    if (options.node !== undefined) {
      return this.readId(op, id, selection, options.node);
    }
    const first = await this.readId(op, id, selection, 0);
    if (first !== null || this.peers.length === 1) {
      return first;
    }
    for (let node = 1; node < this.peers.length; node += 1) {
      const value = await this.readId(op, id, selection, node);
      if (value !== null) {
        return value;
      }
    }
    return null;
  }

  async rpc(node, header, payload = Buffer.alloc(0)) {
    return this.connectionFor(node).rpc(header, payload);
  }

  connectionFor(node) {
    if (node < 0 || node >= this.peers.length) {
      throw new OrbeliasError(`node out of range: ${node}`);
    }
    let conn = this.connections.get(node);
    if (!conn) {
      conn = new OrbeliasConnection(this.peers[node], this.timeoutMs);
      this.connections.set(node, conn);
    }
    return conn;
  }
}

export {
  OrbeliasClient,
  OrbeliasError,
  OrbeliasId,
};

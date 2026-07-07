# RocheDB Protocol / Compatibility Policy

This is the canonical compatibility note for RocheDB's current technical
preview.

## Scope

RocheDB currently exposes two external contracts:

- C ABI: `ROCHE_ABI_VERSION`
- TCP wire protocol: `WIREVER`

Both are intentionally small. They are stable enough for local drivers and
smoke tests, but RocheDB does not yet claim long-term production compatibility
across arbitrary mixed-version clusters.

## Wire Protocol

The wire protocol is a RocheDB-specific text-header protocol with length-prefixed
payloads. It is easy to inspect and fuzz, but compatibility must be managed
explicitly as commands grow.

Rules:

- Clients should check `WIREVER` before assuming command compatibility.
- Minor command additions may preserve the same version only when old clients
  can safely ignore them.
- Any incompatible frame, payload, numeric, or response change must bump
  `WireProtocolVersion`.
- Drivers should prefer high-level named-ring commands such as `PUTR`, `GETID`,
  `QRYID`, `BGET`, `UAPPLY`, and `USTATUS` instead of constructing internal
  placement metadata themselves.

## Vector Byte Order

TCP wire vector bytes are canonical little-endian IEEE-754 `float32` values.
This is now encoded and decoded explicitly in `src/roche/wire.nim`; native wire
drivers must follow the same byte order.

The C ABI is different: C ABI calls accept normal host-native `float` arrays
inside the same process. The ABI boundary does not serialize those floats onto
the network directly.

## Production Readiness Boundaries

RocheDB has username/password/secret-key auth, ring-prefix authorization, simple
RBAC, and deterministic wire fuzz smoke tests. For enterprise production claims,
the remaining gaps are still material:

- TLS and certificate rotation for untrusted networks;
- richer role policy and audit logs;
- cluster transaction coordinator redundancy;
- explicit mixed-version upgrade tests for wire, WAL, snapshots, and drivers.

Until those land, expose `roched` only on trusted networks or behind a tunnel /
proxy that provides transport security.

## Planner Boundary

The default retrieval planner is deterministic heuristic ranking. This is
deliberate: it keeps the DB predictable and avoids embedding a model optimizer
in the core. RocheDB's strongest current evidence is measured working-set and
token reduction under documented synthetic workloads. Broader production claims
must come from larger real-corpus benchmarks and planner improvements.

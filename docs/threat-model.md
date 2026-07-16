# RocheDB Threat Model

This is the canonical English threat model for the current pre-release RocheDB
core. It is intentionally scoped to the open-source core and first-party
drivers.

## Assets

- Stored payloads, vectors, ring names, galaxy names, and atlas descriptions.
- Authentication credentials: username, password, auth token, and secret key.
- Backup artifacts: `roche.log`, JSONL dumps, and encrypted `roche.backup`
  files.
- Cluster transaction landing intents before owner apply.
- Warp belt jobs, progress cursors, retry state, acknowledgements, and
  dead-letter records.
- Operational metadata: health, metrics, ring summaries, and atlas maps.

## Trust Boundaries

- Embedded mode: the application process is trusted. Local filesystem access is
  outside RocheDB's control.
- Cluster mode: each `roched` process is trusted after authentication. The
  network between clients and nodes is not trusted until TLS is implemented.
- Galaxy isolation: separate data directories, peer lists, credentials, and
  secret keys define isolation boundaries.
- Drivers: official drivers must not weaken authentication, ID parsing, or error
  handling compared with the wire protocol.

## In Scope Threats

- Accidental WAL truncation, torn tail records, compact interruption, and partial
  transaction records.
- Cluster owner crash before asynchronous transaction apply.
- Unauthorized access with only username/password or only secret key.
- Backup leakage when plain `backup` / `dump` artifacts are copied outside the
  trusted environment.
- Cross-galaxy confusion caused by connecting to the wrong peer list or data
  directory.

## Current Controls

- Length-prefixed WAL records and replay repair for torn tails.
- Atomic embedded transactions: only transactions with a commit marker replay.
- Cluster landing intents: committed intents remain until applied and are retried
  after owner restart.
- Warp belt jobs are WAL-backed and restore progress / ack state after reopen.
  Acknowledged jobs can be pruned through a tombstone record.
- Read-your-writes fallback through landing intents for `get`, `query`, and
  `batchGet`.
- `durStrong` / `--durability=strong`: flush + fsync write boundaries for
  stronger crash durability.
- Username/password authentication plus secret-key challenge response.
- Ring prefix authorization for named-ring wire operations with
  `roched --allow-ring=prefix[,prefix...]`.
- Minimal role authorization with `reader`, `writer`, and `admin` through
  `roched --role=user:password:role[:prefix1,prefix2]`.
- Wire frame bounds for header, payload, vector, and encrypted transport frame
  lengths. Oversized, negative, or malformed frames return `ERR` and close only
  the offending connection.
- Deterministic malformed-frame smoke coverage in
  `scripts/cluster_wire_fuzz_smoke.sh`.
- Core and cluster smoke entry points are available through
  `scripts/test_core.sh` and `scripts/test_all_smoke.sh`.
- Standard TLS for TCP transport when `roched` and clients are built with
  `-d:ssl`.
- nimsodium secretbox for secret-key auth transport and encrypted backups.
- Galaxy binding in persistent data directories.

## Known Gaps

- TLS is implemented for `roched` TCP transport, but production deployments
  still need certificate issuance, rotation, expiry monitoring, and policy
  management.
- Rich role policies are intentionally not implemented. RocheDB's primary
  isolation model is galaxy separation plus ring-prefix scope; roles are kept
  minimal for read/write/admin separation.
- Cluster transaction coordinator redundancy is not implemented; node0 landing
  remains a single point of failure.
- Online dynamic membership and epoch migration workflows are not implemented.
  The core can model explicit / weighted / virtual arc tables, but operators
  cannot yet apply a live rebalance protocol through the server.
- General database-wide audit logs are not implemented. Warp jobs persist
  attempts, retry timing, acknowledgement, and dead-letter state, but that is
  job state rather than a complete access/change audit trail.
- Server-side warp scheduling is not implemented; applications must call
  `warpStep` / `warpDrain` explicitly in the current core.
- Encrypted backup uses passphrase-derived secretbox encryption. External key
  management and rotation are not implemented.
- Plain `dump` and plain `backup` remain intentionally available and must be
  treated as sensitive artifacts.

## Deployment Guidance

- Use private networks or tunnels until TLS lands.
- Use separate galaxies, credentials, and secret keys for separate trust domains.
- Use `--durability=strong` for data where losing the last flush batch is
  unacceptable.
- Prefer `backup-encrypted` for artifacts that leave the host or trusted storage
  boundary.
- Keep ring and atlas descriptions free of secrets; they are routing metadata,
  not protected payload fields.
- Export `roche metrics` output to CloudWatch, Cloud Monitoring, or a similar
  system and alert on transaction backlog, error growth, auth failures, WAL
  growth, connection pressure, and unexpected restarts.

---
layout: page
title: CLI Reference
---

# CLI Reference

Install the command:

```sh
nimble install orbeliasdb
orbelias --help
```

When working from a source checkout, install the local package onto your PATH:

```sh
nimble install -y
orbelias --help
```

Nimble installs binaries into `~/.nimble/bin` by default. If `orbelias` is not
found, add it to your shell PATH:

```sh
export PATH="$HOME/.nimble/bin:$PATH"
```

For persistent shell setup:

```sh
printf '\nexport PATH="$HOME/.nimble/bin:$PATH"\n' >> ~/.profile
```

For server-style installs, use `/usr/local/bin`:

```sh
nim c -d:release --nimcache:/tmp/nimcache_orbelias -o:bin/orbelias src/orbeliascli.nim
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:bin/orbeliasd src/orbeliasd.nim
sudo install -m 0755 bin/orbelias /usr/local/bin/orbelias
sudo install -m 0755 bin/orbeliasd /usr/local/bin/orbeliasd
```

For repo-local development without installing, you can also build and run a
local binary:

```sh
nim c -d:release --nimcache:/tmp/nimcache_orbelias -o:bin/orbelias src/orbeliascli.nim
bin/orbelias --help
```

## Common Cluster Flags

| Flag | Meaning |
|---|---|
| `--config=FILE` | Load cluster connection defaults from JSON. CLI flags override the file. `ORBELIAS_CONFIG` can point to the same file. |
| `--peers=host:port,...` | Target cluster. |
| `--user=NAME` / `--password=TEXT` | Username/password auth. Prefer `--password-file` or `ORBELIAS_PASSWORD` outside local smoke tests. |
| `--password-file=FILE` | Read password from a file. Trailing whitespace is stripped. |
| `--auth-token=TEXT` | Token-style auth. Prefer `--auth-token-file` or `ORBELIAS_AUTH_TOKEN` outside local smoke tests. |
| `--auth-token-file=FILE` | Read token-style auth value from a file. |
| `--secret-key=TEXT` | Secret-key gate. Prefer `--secret-key-file` or `ORBELIAS_SECRET_KEY` outside local smoke tests. |
| `--secret-key-file=FILE` | Read the secret-key gate value from a file. |
| `--galaxy=NAME` | Expected remote galaxy. |
| `--tls` | Use standard TLS for the TCP transport. Requires TLS-enabled binaries built with `-d:ssl`. |
| `--tls-ca=FILE` | CA/self-signed PEM file for server certificate verification. |
| `--tls-server-name=NAME` | Optional hostname override for TLS verification and SNI. |
| `--tls-insecure-skip-verify` | Skip certificate verification for local smoke tests only. |
| `--metrics` | Emit key/value metrics where supported. |

Example:

```json
{
  "peers": ["127.0.0.1:7301"],
  "user": "alice",
  "passwordFile": "/run/secrets/orbelias_password",
  "secretKeyFile": "/run/secrets/orbelias_secret_key",
  "tls": true,
  "tlsCaFile": "/etc/orbeliasdb/ca.crt"
}
```

```sh
orbelias health --config=/etc/orbeliasdb/client.json
orbelias get --config=/etc/orbeliasdb/client.json --ring=docs/japan
```

## Cluster Commands

| Command | Purpose |
|---|---|
| `health` | Check cluster health. |
| `metrics` | Emit server metrics. |
| `rings` | Show ring summaries. |
| `atlas` | Emit the galaxy/ring map. Works with `--data` or `--peers`. |
| `shutdown` | Stop a server. |
| `demo` | Run a small cluster demo. |

## Driver Commands

OrbeliasDB keeps language drivers small and publishable as language-native
packages. External drivers can live outside the core repository while the
`orbelias` CLI keeps the discovery path consistent.

```sh
orbelias driver list
orbelias driver info rust
orbelias driver install rust
orbelias driver install rust --manifest-path=/path/to/Cargo.toml
```

`driver install` currently prints the official repository/package path and
package-manager command. It does not execute remote scripts or download code.
For Rust it resolves the target `Cargo.toml` in this order:

1. `--manifest-path=FILE`
2. `ORBELIAS_DRIVER_MANIFEST`
3. `--project-dir=DIR`
4. `ORBELIAS_DRIVER_PROJECT`
5. `Cargo.toml` in the current directory

Pass `--execute` to run the package-manager command when the selected driver is
published and the target project can be resolved. OrbeliasDB refuses to execute
package-manager commands for unpublished drivers and prints the command
instead.

| Command | Purpose |
|---|---|
| `driver list` | Show known official driver targets and their publication status. |
| `driver info LANG` | Show repository, package name, mode, and notes for one driver. |
| `driver install LANG` | Print the recommended setup command and target project path. |

## Document Commands

These commands work with `--data=DIR` for embedded mode and `--peers=...` for a
running cluster. When `--data=DIR` is omitted, embedded commands use
`ORBELIAS_DATA` if set, otherwise `./data`.

```sh
orbelias put --ring=docs/japan --payload='{"title":"Hello"}' --codec=json
orbelias get --ring=docs/japan
orbelias put --ring=orders --near=users/123 --payload='{"orderNo":"A-001"}' --codec=json
orbelias get --ring=users/123 --subring=orders
orbelias get --stellar=users/123 --filter='{"kind":"order"}' --subring=orders
orbelias stellar attach --stellar=commerce/order/A-001 --ring=users/123
orbelias stellar detach --stellar=commerce/order/A-001 --ring=users/123
orbelias get --ring=docs/japan --limit=1 --rsort=time
orbelias get --ring=docs/japan --pagination=on --page=2 --pagelimit=20 --sort=id
orbelias get --ring=docs/japan --filter='{"id":"RAW_ID"}' --selection='{ title }'
orbelias get --ring=docs/japan --filter='{"status":"draft"}' --selection='{ title }'
orbelias count-ring --ring=docs/japan
```

Codec is explicit at write time. If you do not pass a codec, OrbeliasDB stores the
payload as `raw` bytes unless `--codec=auto` resolves to a ring profile.

```sh
# JSON document: projection and JSON filters can be used later.
orbelias put --ring=docs/japan --payload='{"title":"Hello","status":"draft"}' --codec=json
orbelias get --ring=docs/japan --filter='{"status":"draft"}' --selection='{ title }'

# NIF text: stored as NIF-tagged bytes. OrbeliasDB does not parse it as JSON.
orbelias put --ring=docs/nif --in=sample.nif --codec=nif
orbelias get --ring=docs/nif --limit=1

# BIF binary: stored as BIF-tagged bytes. `auto` view decodes through an
# optional adapter when available; otherwise it returns base64.
orbelias put --ring=docs/bif --in=sample.bif --codec=bif
orbelias get --ring=docs/bif --limit=1
orbelias get --ring=docs/bif --limit=1 --view=base64
orbelias get --ring=docs/bif --limit=1 --view=hex

# Plain raw bytes or text.
orbelias put --ring=logs/raw --payload='plain text payload' --codec=raw
orbelias get --ring=logs/raw --limit=1
```

| Command | Required flags | Purpose |
|---|---|---|
| `put` | `--ring=RING` plus `--payload=TEXT` or `--in=FILE`; optional `--near=BASE_RING`, `--codec=auto|raw|json|nif|bif` | Store a document and print `id`, `rawId`, resolved ring, and codec. `--near=users/123 --ring=orders` stores into the nearby coordinate `users/123/orders`. `auto` uses the ring profile. |
| `get` | `--ring=RING` or `--stellar=RING`; optional `--subring=a,b`, `--filter=JSON`, `--selection=SEL`, `--limit=N`, `--cursor=CURSOR`, `--sort=id|time`, `--rsort=id|time`, `--pagination=on|off`, `--page=N`, `--pagelimit=N`, `--view=raw|auto|base64|hex` | Read the ring or stellar coordinate's neighborhood. It always returns an `items` array and includes per-ring groups in `rings`. Use `--subring` to narrow the field of view. A `--filter='{"id":"RAW_ID"}'` read stays on the exact ring path for script compatibility. Sorting is applied to the fetched page/filter window, not as a global full-ring sort. The default view is `auto`: payload codec is inferred from stored metadata. |
| `stellar attach` | `--stellar=RING --ring=RING` | Add an existing ring coordinate to a stellar coordinate's visible lens. Payloads are not copied. |
| `stellar detach` | `--stellar=RING --ring=RING` | Remove a ring coordinate from a stellar coordinate's visible lens. Payloads are not deleted. |
| `stellar list` | `--stellar=RING` | List rings attached to a stellar coordinate. |
| `time-orbit` | `--data=DIR --ring=RING`; optional `--bucket-ms=N`, `--bits=N`, `--phase=N`, `--salt=TEXT` | Read or update the embedded ring-local time-orbit profile used by `time-put` and `time-get`. Remote profile administration is not available yet. |
| `time-put` | `--data=DIR --ring=RING --time-ms=N` plus `--payload=TEXT` or `--in=FILE` | Store a log/event payload into the ring's calculated time bucket. JSON object payloads receive `eventTimeMs` and `ingestTimeMs` metadata when missing. |
| `time-get` | `--data=DIR --ring=RING --from-ms=N --to-ms=N`; optional `--filter=JSON`, `--selection=SEL`, `--limit=N`, `--sort=id|time`, `--rsort=id|time` | Calculate the affected time-bucket rings and read only those buckets. The response includes `bucketsVisited`, `rings`, and `items`. |
| `query` | `--ring=RING --filter='{"id":"ID"}' --selection=SEL`; optional `--id=ID` | Compatibility command for JSON projection by ID. Prefer `get --selection=...` for new CLI use. |
| `list-ring` | `--ring=RING` | Compatibility command for listing records in one ring. Prefer `get --ring=...` for new CLI use. |
| `count-ring` | `--ring=RING` | Count records in one ring. |
| `ring-profile` | `--ring=RING` | Read or update the persisted `defaultCodec`, `charset`, and `formatVersion` declaration. |

For example:

```sh
orbelias ring-profile --ring=docs/nif --codec=nif --charset=UTF-8 --format-version=1
orbelias put --ring=docs/nif --payload='(example)' # codec=nif via the profile
```

The profile is advisory. Every record keeps its explicit codec, so a later
profile change does not reinterpret existing bytes. Remote profile
administration is not available in this release.

Time orbit is an embedded PoC for log/event/time-series placement:

```sh
orbelias time-orbit --ring=logs/api --bucket-ms=1000 --bits=60 --phase=100 --salt=api
orbelias time-put --ring=logs/api --time-ms=1784376000000 \
  --payload='{"level":"error","message":"timeout"}'
orbelias time-get --ring=logs/api --from-ms=1784376000000 --to-ms=1784376300000 \
  --filter='{"level":"error"}' --selection='{ level message eventTimeMs }'
```

`--filter` is a JSON object. `{"id":"RAW_ID"}` performs an exact read, while
other top-level fields filter JSON records in the selected ring. `--where` is
accepted as a compatibility alias for `--filter`.

`--near` is a write-time placement hint, not a persistent relationship field.
For example, `orbelias put --near=users/123 --ring=orders ...` writes the record to
`users/123/orders`. Later reads use the coordinate itself:

```sh
orbelias get --ring=users/123
orbelias get --stellar=users/123 --filter='{"kind":"order"}' --subring=orders
orbelias get --ring=users/123/orders
orbelias get --ring=users/123 --subring=orders
```

This is similar to pointing a telescope at a ring. Nearby satellites are in the
same field of view; distant rings are not pulled in just to emulate a global
join.

`stellar attach` and `stellar detach` adjust a stellar coordinate's lens after
data already exists:

```sh
orbelias put --ring=users/123 --payload='{"kind":"user"}' --codec=json
orbelias put --ring=shops/1123 --payload='{"kind":"shop"}' --codec=json
orbelias put --ring=orders/A-001 --payload='{"kind":"order"}' --codec=json

orbelias stellar attach --stellar=commerce/order/A-001 --ring=users/123
orbelias stellar attach --stellar=commerce/order/A-001 --ring=shops/1123
orbelias stellar attach --stellar=commerce/order/A-001 --ring=orders/A-001

orbelias get --stellar=commerce/order/A-001 --filter='{"kind":"shop"}'
orbelias stellar detach --stellar=commerce/order/A-001 --ring=shops/1123
```

This is a lens relationship, not a copy operation. Compaction can later use the
same metadata to place related coordinates more favorably on disk.

`--sort=FIELD` sorts ascending and `--rsort=FIELD` sorts descending. Supported
fields are `id` and `time` (`write` is accepted as a compatibility alias for
`time`). The default is `--rsort=time`. `--pagination=on --page=N
--pagelimit=N` is a human-friendly page interface. For high-volume scans,
prefer cursor-based reads with `--cursor` because deep pages must skip earlier
filtered matches.

For BIF payloads, the default `auto` view looks for an optional adapter in this
order: `ORBELIASDB_NIF_TOOL`, `orbeliasdb-nif`, then `nif_file_tool`. The adapter
command must support:

```sh
ADAPTER decode --in=input.bif --out=output.nif
```

ID formats accepted by `get` and `query`:

- `parent:seq`
- `parent:epoch:seq:tWrite`

Use the `rawId` printed by `put` for scripts and reproducible examples.

## Interactive Shell

`orbelias shell` provides a small MySQL-like interactive command surface for manual
exploration:

```sh
orbelias shell
```

Minimal shell commands:

```text
put RING PAYLOAD
get ID [RING]
query ID SELECTION
query ID RING SELECTION  # cluster mode
list RING [LIMIT]
count RING
atlas
help
exit
```

The shell intentionally uses OrbeliasDB terms directly. It is not an SQL parser.
For scripts and reproducible examples, prefer the single-shot commands above.

## Local Data Commands

| Command | Required flags | Purpose |
|---|---|---|
| `compact` | `--data=DIR` | Compact WAL. |
| `locality` | `--data=DIR`; optional `--metrics` | Inspect physical WAL locality by ring. |
| `backup` | `--data=DIR --backup=DIR` | Create backup. |
| `restore` | `--backup=DIR --data=DIR` | Restore backup. |
| `backup-encrypted` | `--data=DIR --backup=DIR --passphrase=TEXT` | Create encrypted backup. |
| `restore-encrypted` | `--backup=DIR --data=DIR --passphrase=TEXT` | Restore encrypted backup. |
| `dump` | `--data=DIR` | Export JSONL. |
| `import-jsonl` | `--data=DIR --in=FILE` | Import JSONL. |
| `describe-galaxy` | `--data=DIR --description=TEXT` | Set galaxy map description. |
| `describe-ring` | `--data=DIR --ring=RING --description=TEXT` | Set ring map description. |

`dump` / `import-jsonl` are the portable migration boundary while OrbeliasDB's
pre-v1.0 internal WAL format can still evolve. `import-jsonl` recognizes
`orbeliasdb.dump.v1` files produced by `dump`, and can also route external JSONL
exports through `--ring-field`, `--payload-field`, and `--vec-field`. See
[Data Migration](data-migration.md).

## Recovery Commands

| Command | Purpose |
|---|---|
| `recovery-backup` | Write recovery archives from a data directory. |
| `recovery-verify` | Verify one recovery archive. |
| `recovery-status` | Check archive health against `requiredHealthy`. |
| `recovery-restore` | Restore from the best healthy archive. |

Recovery commands accept `--mirror`, `--universe-config`, `--universe`,
`--galaxy`, `--location`, `--failure-domain`, `--priority`, `--snapshot-seq`,
`--auth-ref`, `--readonly`, and `--passphrase` where applicable.

## Universe Sync Commands

| Command | Purpose |
|---|---|
| `universe-export --data=DIR [--out=FILE]` | Export source outbox events. |
| `universe-apply --data=DIR --in=FILE` | Apply exported events to a local data directory. |
| `universe-sync --data=SOURCE --target-data=TARGET` | One-shot local sync. |
| `universe-sync --data=SOURCE --peers=host:port,...` | Deliver source outbox events to a running cluster. |
| `universe-status --data=DIR` | Inspect source outbox status. |
| `universe-status --peers=host:port,... --metrics` | Inspect remote apply counters. |

## Benchmark / Demo Commands

| Command | Purpose |
|---|---|
| `bench` | Basic cluster operation benchmark. |
| `retrieve-bench` | Retrieval benchmark. |
| `redis-bench` | Redis comparison smoke. |
| `rag-bench` | Synthetic RAG-style working-set/token benchmark. |
| `working-set-bench` | Working-set reduction benchmark. |
| `memory-pressure-bench` | Candidate memory pressure benchmark. |
| `doctor` | Check optional native dependencies such as FAISS bridge. |

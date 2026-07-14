---
layout: page
title: CLI Reference
---

# CLI Reference

Install the command:

```sh
nimble install rochedb
roche --help
```

When working from a source checkout, install the local package onto your PATH:

```sh
nimble install -y
roche --help
```

Nimble installs binaries into `~/.nimble/bin` by default. If `roche` is not
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
nim c -d:release --nimcache:/tmp/nimcache_roche -o:bin/roche src/rochecli.nim
nim c -d:release --nimcache:/tmp/nimcache_roched -o:bin/roched src/roched.nim
sudo install -m 0755 bin/roche /usr/local/bin/roche
sudo install -m 0755 bin/roched /usr/local/bin/roched
```

For repo-local development without installing, you can also build and run a
local binary:

```sh
nim c -d:release --nimcache:/tmp/nimcache_roche -o:bin/roche src/rochecli.nim
bin/roche --help
```

## Common Cluster Flags

| Flag | Meaning |
|---|---|
| `--peers=host:port,...` | Target cluster. |
| `--user=NAME` / `--password=TEXT` | Username/password auth. |
| `--auth-token=TEXT` | Token-style auth. |
| `--secret-key=TEXT` | Secret-key gate. |
| `--galaxy=NAME` | Expected remote galaxy. |
| `--tls` | Use standard TLS for the TCP transport. Requires TLS-enabled binaries built with `-d:ssl`. |
| `--tls-ca=FILE` | CA/self-signed PEM file for server certificate verification. |
| `--tls-server-name=NAME` | Optional hostname override for TLS verification and SNI. |
| `--tls-insecure-skip-verify` | Skip certificate verification for local smoke tests only. |
| `--metrics` | Emit key/value metrics where supported. |

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

RocheDB keeps language drivers small and publishable as language-native
packages. External drivers can live outside the core repository while the
`roche` CLI keeps the discovery path consistent.

```sh
roche driver list
roche driver info rust
roche driver install rust
roche driver install rust --manifest-path=/path/to/Cargo.toml
```

`driver install` currently prints the official repository/package path and
package-manager command. It does not execute remote scripts or download code.
For Rust it resolves the target `Cargo.toml` in this order:

1. `--manifest-path=FILE`
2. `ROCHE_DRIVER_MANIFEST`
3. `--project-dir=DIR`
4. `ROCHE_DRIVER_PROJECT`
5. `Cargo.toml` in the current directory

Pass `--execute` to run the package-manager command when the selected driver is
published and the target project can be resolved. RocheDB refuses to execute
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
`ROCHE_DATA` if set, otherwise `./data`.

```sh
roche put --ring=docs/japan --payload='{"title":"Hello"}' --codec=json
roche get --ring=docs/japan
roche get --ring=docs/japan --limit=1 --rsort=time
roche get --ring=docs/japan --pagination=on --page=2 --pagelimit=20 --sort=id
roche get --ring=docs/japan --filter='{"id":"RAW_ID"}' --selection='{ title }'
roche get --ring=docs/japan --filter='{"status":"draft"}' --selection='{ title }'
roche count-ring --ring=docs/japan
```

Codec is explicit at write time. If you do not pass a codec, RocheDB stores the
payload as `raw` bytes unless `--codec=auto` resolves to a ring profile.

```sh
# JSON document: projection and JSON filters can be used later.
roche put --ring=docs/japan --payload='{"title":"Hello","status":"draft"}' --codec=json
roche get --ring=docs/japan --filter='{"status":"draft"}' --selection='{ title }'

# NIF text: stored as NIF-tagged bytes. RocheDB does not parse it as JSON.
roche put --ring=docs/nif --in=sample.nif --codec=nif
roche get --ring=docs/nif --limit=1

# BIF binary: stored as BIF-tagged bytes. `auto` view decodes through an
# optional adapter when available; otherwise it returns base64.
roche put --ring=docs/bif --in=sample.bif --codec=bif
roche get --ring=docs/bif --limit=1
roche get --ring=docs/bif --limit=1 --view=base64
roche get --ring=docs/bif --limit=1 --view=hex

# Plain raw bytes or text.
roche put --ring=logs/raw --payload='plain text payload' --codec=raw
roche get --ring=logs/raw --limit=1
```

| Command | Required flags | Purpose |
|---|---|---|
| `put` | `--ring=RING` plus `--payload=TEXT` or `--in=FILE`; optional `--codec=auto|raw|json|nif|bif` | Store a document and print `id`, `rawId`, and codec. `auto` uses the ring profile. |
| `get` | `--ring=RING`; optional `--filter=JSON`, `--selection=SEL`, `--limit=N`, `--cursor=CURSOR`, `--sort=id|time`, `--rsort=id|time`, `--pagination=on|off`, `--page=N`, `--pagelimit=N`, `--view=raw|auto|base64|hex` | Read from one ring. It always returns an `items` array with returned-item `count` and `nextCursor`; use `--limit=1` when you only want one item. Sorting is applied to the fetched page/filter window, not as a global full-ring sort. The default view is `auto`: payload codec is inferred from stored metadata. |
| `query` | `--ring=RING --filter='{"id":"ID"}' --selection=SEL`; optional `--id=ID` | Compatibility command for JSON projection by ID. Prefer `get --selection=...` for new CLI use. |
| `list-ring` | `--ring=RING` | Compatibility command for listing records in one ring. Prefer `get --ring=...` for new CLI use. |
| `count-ring` | `--ring=RING` | Count records in one ring. |
| `ring-profile` | `--ring=RING` | Read or update the persisted `defaultCodec`, `charset`, and `formatVersion` declaration. |

For example:

```sh
roche ring-profile --ring=docs/nif --codec=nif --charset=UTF-8 --format-version=1
roche put --ring=docs/nif --payload='(example)' # codec=nif via the profile
```

The profile is advisory. Every record keeps its explicit codec, so a later
profile change does not reinterpret existing bytes. Remote profile
administration is not available in this release.

`--filter` is a JSON object. `{"id":"RAW_ID"}` performs an exact read, while
other top-level fields filter JSON records in the selected ring. `--where` is
accepted as a compatibility alias for `--filter`.

`--sort=FIELD` sorts ascending and `--rsort=FIELD` sorts descending. Supported
fields are `id` and `time` (`write` is accepted as a compatibility alias for
`time`). The default is `--rsort=time`. `--pagination=on --page=N
--pagelimit=N` is a human-friendly page interface. For high-volume scans,
prefer cursor-based reads with `--cursor` because deep pages must skip earlier
filtered matches.

For BIF payloads, the default `auto` view looks for an optional adapter in this
order: `ROCHEDB_NIF_TOOL`, `rochedb-nif`, then `nif_file_tool`. The adapter
command must support:

```sh
ADAPTER decode --in=input.bif --out=output.nif
```

ID formats accepted by `get` and `query`:

- `parent:seq`
- `parent:epoch:seq:tWrite`

Use the `rawId` printed by `put` for scripts and reproducible examples.

## Interactive Shell

`roche shell` provides a small MySQL-like interactive command surface for manual
exploration:

```sh
roche shell
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

The shell intentionally uses RocheDB terms directly. It is not an SQL parser.
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

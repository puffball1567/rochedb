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
```

`driver install` currently prints the official repository/package path and setup
command. It does not execute remote scripts or download code. This keeps the
bootstrap path safe while preserving a single command surface for Rust, Node,
PHP, Python, Go, and later drivers.

| Command | Purpose |
|---|---|
| `driver list` | Show known official driver targets and their publication status. |
| `driver info LANG` | Show repository, package name, mode, and notes for one driver. |
| `driver install LANG` | Print the recommended setup command and follow-up smoke-test path. |

## Document Commands

These commands work with `--data=DIR` for embedded mode and `--peers=...` for a
running cluster.

```sh
roche put --data=data --ring=docs/japan --payload='{"title":"Hello"}'
roche list-ring --data=data --ring=docs/japan
roche get --data=data --id=RAW_ID
roche query --data=data --id=RAW_ID --selection='{ title }'
roche count-ring --data=data --ring=docs/japan
```

| Command | Required flags | Purpose |
|---|---|---|
| `put` | `--ring=RING` plus `--payload=TEXT` or `--in=FILE` | Store a document and print `id` plus `rawId`. |
| `get` | `--id=ID` | Fetch one document by ID. Cluster mode also requires `--ring=RING`. |
| `query` | `--id=ID --selection=SEL` | Fetch a JSON projection. Cluster mode also requires `--ring=RING`. |
| `list-ring` | `--ring=RING` | List records in one ring. |
| `count-ring` | `--ring=RING` | Count records in one ring. |

ID formats accepted by `get` and `query`:

- `parent:seq`
- `parent:epoch:seq:tWrite`

Use the `rawId` printed by `put` for scripts and reproducible examples.

## Interactive Shell

`roche shell` provides a small MySQL-like interactive command surface for manual
exploration:

```sh
roche shell --data=data
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

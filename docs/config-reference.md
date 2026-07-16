---
layout: page
title: Configuration Reference
---

# Configuration Reference

This page collects the main configuration surfaces. Topology JSON has its own
full reference in [Topology Configuration](topology-config.md).

## Embedded Open

| Property | Type | Default | Meaning |
|---|---:|---:|---|
| `nodes` | integer | `8` | Logical node count for embedded placement calculations. |
| `dataDir` | string | `""` | Empty means memory-only. Non-empty enables WAL persistence. |
| `durability` | enum | `durBuffered` | `durBuffered` batches flushes; `durStrong` adds flush/fsync boundaries. |

## Cluster Connect

| Property | Type | Default | Meaning |
|---|---:|---:|---|
| `peers` | string | required | Comma-separated `host:port` list. |
| `username` | string | `""` | Username for password auth. |
| `password` | string | `""` | Password for username auth. |
| `authToken` | string | `""` | Token-style auth convenience path. |
| `secretKey` | string | `""` | Additional secret-key gate and encrypted auth transport. |
| `galaxy` | string | `""` | Expected remote galaxy name. |
| `tls` | bool | `false` | Use standard TLS for the TCP transport. Requires binaries built with `-d:ssl`. |
| `tlsCaFile` | string | `""` | CA/self-signed PEM file for server certificate verification. |
| `tlsServerName` | string | `""` | Optional hostname override for TLS verification and SNI. |
| `tlsInsecureSkipVerify` | bool | `false` | Skip certificate verification for local smoke tests only. |

The CLI can load these connection defaults from JSON with `--config=FILE` or
`ROCHE_CONFIG=FILE`. Command-line flags override the file.

```json
{
  "peers": ["127.0.0.1:7301", "127.0.0.1:7302"],
  "user": "alice",
  "password": "change-me",
  "secretKey": "change-me-too",
  "galaxy": "default",
  "tls": true,
  "tlsCaFile": "/etc/rochedb/ca.crt",
  "tlsServerName": "rochedb.internal",
  "tlsInsecureSkipVerify": false
}
```

`peers` may be either a comma-separated string or an array of `host:port`
strings. The CLI accepts the documented camelCase fields and their flag-style
aliases such as `secret-key`, `auth-token`, `tls-ca`, and `tls-server-name`.
Keep production config files outside the repository, lock down file
permissions, and prefer external secret injection when the deployment platform
provides it.

## `roched` Server Flags

| Flag | Meaning |
|---|---|
| `--id=N` | Node index in the peer list. |
| `--peers=host:port,...` | Static cluster peer list. |
| `--data=DIR` | Persistent data directory. |
| `--slow-tick=SECONDS` | Background handoff / maintenance tick interval. |
| `--durability=buffered|strong` | WAL durability policy. |
| `--user=NAME` / `--password=TEXT` | Basic username/password gate. |
| `--secret-key=TEXT` | Secret-key gate and secure auth transport. |
| `--auth-token=TEXT` | Token-style auth convenience path. |
| `--tls-cert=FILE` / `--tls-key=FILE` | Enable standard TLS for the TCP listener. Requires `-d:ssl`. |
| `--tls-ca=FILE` | CA/self-signed PEM file used by the server's peer client. |
| `--tls-server-name=NAME` | Optional hostname override for peer TLS verification and SNI. |
| `--tls-insecure-skip-verify` | Skip peer certificate verification for local smoke tests only. |
| `--galaxy=NAME` | Galaxy identity expected by clients. |
| `--allow-ring=PREFIX[,PREFIX...]` | Ring-prefix authorization boundary. |
| `--role=user:password:reader|writer|admin[:prefixes]` | Role and optional ring-prefix policy. |

## Retrieval Tuning

Prefer `SearchProfile` for application-facing settings:

| Property | Values | Meaning |
|---|---|---|
| `amount` | `raFew`, `raNormal`, `raMany`, `raAllUseful` | How many useful results to retain. |
| `scope` | `ssTight`, `ssNear`, `ssWide`, `ssAll` | How broadly to search related rings. |
| `depth` | `sdShallow`, `sdNormal`, `sdDeep`, `sdVeryDeep` | How far to descend ring hierarchy. |

Lower-level knobs are still available:

| Property | Range / Default | Meaning |
|---|---:|---|
| `budget` | default `8` | Max returned retrieval hits. |
| `focus` | `0..100` | Human-facing breadth control. It maps to effective top-ring selection. |
| `topRings` | clamped internally | Direct top-ring candidate count for advanced tuning. |
| `branchBudget` | `0` means default | Per-branch hierarchy breadth. |
| `maxDepth` | `0` means no descent | Child-ring depth. |
| `includeChildren` | `false` | Include descendant rings. |

## Write Acknowledgement

| Value | Meaning |
|---|---|
| `wamAccepted` | Return after durable landing/intake. |
| `wamApplied` | Return after owner apply. |

Use `configureWriteAckMode` for the default and
`configureRingWriteAckMode` for ring-specific overrides.

## Ring Apply Policy

| Property | Type | Meaning |
|---|---:|---|
| `mode` | enum | Universe sync apply behavior. |
| `historyKeep` | integer | Bounded history size for modes that keep history. |
| `delayMs` | integer | Delay window before timestamp-ordered apply. |

Modes:

| Mode | Meaning |
|---|---|
| `ramLatestOnly` | Keep the newest logical value. |
| `ramAppendOnly` | Append timestamped data while deduplicating event IDs. |
| `ramBoundedHistory` | Keep bounded history for future undo/redo-style use. |
| `ramDelayedTimestamp` | Delay application to preserve timestamp order. |

## Topology JSON

Use [Topology Configuration](topology-config.md) for universe / galaxy recovery
layouts. The important top-level fields are:

| Field | Meaning |
|---|---|
| `version` | Schema marker. Use `1`. |
| `requiredHealthy` | Minimum healthy recovery archives. |
| `authProfiles` | Named references to external secret locations. |
| `universes` | Parallel placements. Each universe contains the same galaxy names. |

Do not store raw `username`, `password`, or `secretKey` values in topology JSON.

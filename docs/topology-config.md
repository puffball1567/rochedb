# OrbeliasDB Topology Configuration

This is the reference for OrbeliasDB recovery / universe topology files. For
deployment patterns, see [topology-examples.md](./topology-examples.md). For
cloud metrics and recovery commands, see [cloud-operations.md](./cloud-operations.md).

The topology file is JSON.

## Minimal Example

```json
{
  "version": 1,
  "requiredHealthy": 1,
  "universes": [
    {
      "universe": "local-a",
      "location": "local",
      "galaxies": [
        {
          "galaxy": "app-main",
          "archive": "/backup/orbeliasdb/app-main/local-a"
        }
      ]
    }
  ]
}
```

Run:

```sh
orbelias recovery-backup --data=/var/lib/orbeliasdb \
  --universe-config=/etc/orbeliasdb/topology.json

orbelias recovery-status --universe-config=/etc/orbeliasdb/topology.json \
  --metrics

orbelias recovery-restore --universe-config=/etc/orbeliasdb/topology.json \
  --data=/var/lib/orbeliasdb-restored
```

## Full Example

```json
{
  "version": 1,
  "requiredHealthy": 2,
  "authProfiles": {
    "shared-ai": {
      "mode": "user-password-secret-key",
      "source": "secret-manager:orbelias/shared-ai"
    },
    "audit-readonly": {
      "mode": "user-password-secret-key",
      "source": "secret-manager:orbelias/audit-readonly"
    }
  },
  "universes": [
    {
      "universe": "tokyo-a",
      "location": "local",
      "failureDomain": "aws-ap-northeast-1",
      "authRef": "shared-ai",
      "priority": 10,
      "snapshotSeq": 1001,
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/orbeliasdb/training-data/tokyo-a"
        },
        {
          "galaxy": "prompt-cache",
          "archive": "/backup/orbeliasdb/prompt-cache/tokyo-a",
          "authRef": "audit-readonly",
          "readonly": false
        }
      ]
    },
    {
      "universe": "oregon-a",
      "location": "remote",
      "endpoint": "orbelias://oregon-training.internal:7301",
      "failureDomain": "aws-us-west-2",
      "authRef": "shared-ai",
      "priority": 5,
      "snapshotSeq": 1000,
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/orbeliasdb/training-data/oregon-a"
        },
        {
          "galaxy": "prompt-cache",
          "archive": "/backup/orbeliasdb/prompt-cache/oregon-a",
          "authRef": "audit-readonly",
          "readonly": true
        }
      ]
    }
  ]
}
```

## Top-Level Fields

| Field | Type | Required | Meaning |
|---|---:|---:|---|
| `version` | integer | No | Configuration schema marker. Use `1`. |
| `requiredHealthy` | integer | No | Minimum healthy archive count required by `recovery-status`. CLI `--required-healthy` overrides it. |
| `authProfiles` | object | No | Named galaxy authentication profile references. Secrets are not stored here. |
| `universes` | array | Yes | Parallel universe placements. Each universe must contain the same galaxy names. |

## `authProfiles`

`authProfiles` declares names that galaxy placements can reference through
`authRef`.

```json
{
  "authProfiles": {
    "shared-ai": {
      "mode": "user-password-secret-key",
      "source": "secret-manager:orbelias/shared-ai"
    }
  }
}
```

| Field | Type | Required | Meaning |
|---|---:|---:|---|
| `mode` | string | No | Must be `user-password-secret-key` when present. This is also the default. |
| `source` | string | No | Operator-defined location of the real credentials, such as a secret manager path. |

Do not include `username`, `password`, or `secretKey` in the topology file.
OrbeliasDB rejects those fields under `authProfiles`.

## `universes[]`

Each universe is a parallel placement of the same galaxy names.

| Field | Type | Required | Meaning |
|---|---:|---:|---|
| `universe` | string | Recommended | Logical universe name, such as `tokyo-a` or `oregon-a`. |
| `location` | string | No | `local` or `remote`. Defaults to `local`. |
| `endpoint` | string | Required for remote | Physical endpoint hint for a remote placement. |
| `failureDomain` | string | No | Operator-defined domain such as region, AZ, rack, or provider. |
| `authRef` | string | No | Default galaxy authentication profile for this universe. Must exist in `authProfiles` when `authProfiles` is declared. |
| `priority` | integer | No | Higher priority wins when multiple healthy restore candidates exist. |
| `snapshotSeq` | integer | No | Higher snapshot sequence wins after priority tie. |
| `readonly` | boolean | No | Default for galaxies in this universe. |
| `enabled` | boolean | No | Disabled universes are ignored. Defaults to `true`. |
| `galaxies` | array | Yes | Galaxy placements inside this universe. |

Rules:

- `location` must be `local` or `remote`.
- `remote` universes require `endpoint`.
- Endpoint is not identity. Different universes may point at the same endpoint.
- A universe may host multiple galaxies at one endpoint.
- Duplicate galaxy names inside one universe are rejected.

## `universes[].galaxies[]`

Each entry describes one galaxy placement in one universe.

| Field | Type | Required | Meaning |
|---|---:|---:|---|
| `galaxy` | string | Yes | Galaxy name. |
| `archive` | string | Yes | Recovery archive path. |
| `authRef` | string | No | Overrides universe-level `authRef`. |
| `readonly` | boolean | No | Read/verify/restore allowed, but `recovery-backup` will not write this placement. |
| `enabled` | boolean | No | Disabled placements are ignored. Defaults to `true`. |

Aliases:

- `mirror` and `path` are accepted as aliases for `archive` for compatibility.

## Galaxy Set Rule

Every universe in one topology must contain the same galaxy names.

Valid:

```text
tokyo-a:  training-data, prompt-cache
oregon-a: training-data, prompt-cache
```

Invalid:

```text
tokyo-a:  training-data, prompt-cache
oregon-a: training-data
```

This rule keeps recovery and future replication targets unambiguous.

## Restore Candidate Selection

`recovery-restore` chooses among healthy archives by:

1. Higher `priority`
2. Higher `snapshotSeq`
3. Archive path as a stable tie-breaker

`readonly` archives remain eligible for verification and restore. They are only
excluded as write targets during `recovery-backup`.

## CLI Overrides

The recovery CLI can create entries without a topology file:

```sh
orbelias recovery-backup --data=/var/lib/orbeliasdb \
  --mirror=/backup/app-main \
  --universe=local-a \
  --galaxy=app-main \
  --location=local \
  --auth-ref=shared-ai \
  --priority=10 \
  --snapshot-seq=1001
```

For multi-galaxy or local/remote layouts, prefer a topology JSON file.

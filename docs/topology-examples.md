# RocheDB Topology Pattern Catalog

This document is a pattern catalog for mapping RocheDB's universe / galaxy /
ring model to real deployments. Use it like a cloud design-pattern guide:
choose what you want to build, copy the closest topology, then simplify it.
Start simple. Add universes, remote placements, and shared galaxy
authentication profiles only when they solve an operational problem.

## Mental Model

| Term | Practical meaning |
|---|---|
| `galaxy` | One RocheDB database, data boundary, and authentication boundary |
| `ring` | A table-like locality and retrieval scope inside one galaxy |
| `universe` | A parallel placement of the same galaxy names for recovery and future replication |
| `endpoint` | Physical placement hint; not galaxy identity |
| `authRef` | Reference to a galaxy authentication profile |
| `readonly` | Read and restore are allowed, but this placement is not a write target |

Rules that keep the topology safe:

- One RocheDB instance should normally represent one galaxy.
- Every universe in one topology must contain the same galaxy names.
- The same endpoint may host multiple galaxies.
- Different universes may point at the same endpoint.
- Duplicate galaxy names inside one universe are rejected.
- Do not put usernames, passwords, or secret keys in topology files.

## Pattern 1. Single Local Galaxy

### Use When

You want the smallest useful RocheDB deployment for local development, embedded
tools, a small service, or the first production test.

### Shape

```text
universe: local
  galaxy: app-main
    rings: tenant/acme/orders, tenant/acme/users, docs/support
```

### Docker Compose Demo

```sh
docker compose -f examples/compose/single-galaxy.compose.yml up --build
```

### Manual Equivalent

Run one server:

```sh
bin/roched --id=0 --peers=127.0.0.1:7301 \
  --data=.data/app-main \
  --galaxy=app-main \
  --user=app --password=change-me --secret-key=change-me-too
```

Use rings to express locality:

```text
tenant/acme/orders/2026
tenant/acme/users
docs/support/japan
```

### Tradeoffs

This is easy to operate and understand. It does not provide cross-region
recovery or strong blast-radius isolation between unrelated datasets.

## Pattern 2. Separate Galaxies for Blast-Radius Control

### Use When

Two datasets should not share credentials, data directories, or operational
policy.

### Shape

```text
galaxy: training-data
galaxy: prompt-cache
galaxy: audit-log
```

### Manual Equivalent

Each galaxy can run as a separate RocheDB instance:

```sh
bin/roched --id=0 --peers=127.0.0.1:7311 --data=.data/training-data \
  --galaxy=training-data --user=train --password=... --secret-key=...

bin/roched --id=0 --peers=127.0.0.1:7321 --data=.data/prompt-cache \
  --galaxy=prompt-cache --user=cache --password=... --secret-key=...
```

Choose this when compromise of one dataset must not imply compromise of the
others.

### Tradeoffs

This is stronger for security and failure isolation, but it increases the number
of credentials, processes, metrics streams, and backups you must operate.

## Pattern 3. Same Galaxy Auth Profile for Multiple Galaxies

### Use When

Operational simplicity matters more than maximum isolation. The topology file
references a profile name only; the real credentials still live in a secret
manager or runtime environment.

### Shape

```json
{
  "authProfiles": {
    "shared-ai": {
      "mode": "user-password-secret-key",
      "source": "secret-manager:roche/shared-ai"
    }
  },
  "universes": [
    {
      "universe": "local-a",
      "location": "local",
      "authRef": "shared-ai",
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/training-data/local-a"
        },
        {
          "galaxy": "prompt-cache",
          "archive": "/backup/prompt-cache/local-a"
        }
      ]
    }
  ]
}
```

This is convenient, but it increases blast radius compared with separate
profiles per galaxy.

### Tradeoffs

Use this deliberately. It is convenient for teams that want one operational
credential set, but a compromised profile can affect every galaxy that uses it.

## Pattern 4. Local + Remote Recovery Universe

### Use When

You want a local recovery copy and a remote recovery copy with the same galaxy
names.

### Shape

```json
{
  "version": 1,
  "requiredHealthy": 2,
  "authProfiles": {
    "shared-ai": {
      "mode": "user-password-secret-key",
      "source": "secret-manager:roche/shared-ai"
    }
  },
  "universes": [
    {
      "universe": "tokyo-a",
      "location": "local",
      "authRef": "shared-ai",
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/training-data/tokyo-a"
        },
        {
          "galaxy": "prompt-cache",
          "archive": "/backup/prompt-cache/tokyo-a"
        }
      ]
    },
    {
      "universe": "oregon-a",
      "location": "remote",
      "endpoint": "roche://oregon.example.internal:7301",
      "authRef": "shared-ai",
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/training-data/oregon-a"
        },
        {
          "galaxy": "prompt-cache",
          "archive": "/backup/prompt-cache/oregon-a",
          "readonly": true
        }
      ]
    }
  ]
}
```

`readonly` is useful for remote, restore-only, audit, or analysis placements.
It does not make the archive unhealthy; it only means RocheDB should not write
there during `recovery-backup`.

### Tradeoffs

This improves disaster-recovery posture without making the endpoint part of
galaxy identity. Recovery is only as good as the backup cadence, secret manager
policy, and restore drills around it.

## Pattern 5. Same Endpoint, Different Galaxies

### Use When

One physical node, host, or service endpoint runs multiple RocheDB galaxies.
This often happens in small staging environments, local demos, or consolidated
internal services.

This is allowed. Endpoint is physical placement, not identity.

```json
{
  "universes": [
    {
      "universe": "rack-a",
      "location": "remote",
      "endpoint": "roche://node-a.internal:7301",
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/training-data/rack-a"
        },
        {
          "galaxy": "audit-log",
          "archive": "/backup/audit-log/rack-a"
        }
      ]
    },
    {
      "universe": "rack-b",
      "location": "remote",
      "endpoint": "roche://node-a.internal:7301",
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/training-data/rack-b"
        },
        {
          "galaxy": "audit-log",
          "archive": "/backup/audit-log/rack-b"
        }
      ]
    }
  ]
}
```

This remains valid because each universe has the same galaxy names.

### Tradeoffs

This is operationally compact, but endpoint failure affects every galaxy hosted
there. It is valid topology, not a high-isolation production pattern.

## Pattern 6. Invalid: Duplicate Galaxy in One Universe

### Why Invalid

Do not do this:

```json
{
  "universes": [
    {
      "universe": "bad-a",
      "location": "local",
      "galaxies": [
        {
          "galaxy": "training-data",
          "archive": "/backup/training-data/a"
        },
        {
          "galaxy": "training-data",
          "archive": "/backup/training-data/b"
        }
      ]
    }
  ]
}
```

RocheDB rejects this because the archive and policy target are ambiguous.

## Pattern 7. Three-Node Galaxy Cluster

### Use When

You want to test RocheDB's cluster wire path and one galaxy spread across
multiple nodes.

### Docker Compose Demo

```sh
docker compose -f examples/compose/three-node-galaxy.compose.yml up --build
```

### Shape

```text
galaxy: training-data
  node0: roche-node0:7301
  node1: roche-node1:7301
  node2: roche-node2:7301
```

### Tradeoffs

This demonstrates cluster behavior, but it is still one galaxy. Use separate
galaxies when you need separate credentials or blast-radius boundaries.

## Pattern 8. Local/Remote Universe Demo

### Use When

You want a visible local/remote style topology with multiple galaxies.

### Process Demo

```sh
examples/local_remote_galaxy_demo.sh
```

The script starts four RocheDB instances:

```text
training-data local
training-data remote
prompt-cache local
prompt-cache remote
```

Then it connects with the matching galaxy credentials and writes a small record
to each placement. This is the quickest way to see that galaxy identity and
local/remote endpoint placement are separate concerns.

### Docker Compose Demo

```sh
docker compose -f examples/compose/local-remote-universe.compose.yml up --build
```

### Shape

```text
universe: local
  galaxy: training-data
  galaxy: prompt-cache

universe: remote
  galaxy: training-data
  galaxy: prompt-cache
```

### Tradeoffs

This is useful for explaining the concept. In production, place remote
universes on truly independent infrastructure and validate recovery with
`roche recovery-status` and restore drills.

## Pattern 9. Durable Universe Sync Demo

### Use When

You want to see the eventual-sync boundary without adding remote transport or a
long-running scheduler.

### Process Demo

```sh
examples/universe_sync_demo.sh
```

The local demo script creates separate source and target data directories,
enqueues a universe sync event, applies it idempotently to the target,
acknowledges it in the source outbox, and prunes the acknowledged event. It
then repeats the same boundary through `roche universe-export` and
`roche universe-sync`.

Remote delivery uses the same source outbox but sends events to a running
RocheDB server:

```sh
roche universe-status --data=/var/lib/roche-source
roche universe-sync --data=/var/lib/roche-source \
  --peers=remote-roche.internal:7301 --prune-acked
roche universe-status --peers=remote-roche.internal:7301
```

Runnable remote smoke:

```sh
scripts/universe_sync_remote_smoke.sh
```

The remote smoke verifies that a down target leaves the source event pending,
then starts the target, retries delivery, applies the event, acknowledges it,
prunes the source outbox, and exposes remote apply counters through
`universe-status --peers --metrics`.

See [Universe Sync](universe-sync.md) for the sync model, status commands,
metrics, and failure behavior.

### Shape

```text
universe: tokyo
  galaxy: social
    ring: posts/u1
    outbox: pending event

universe: oregon
  galaxy: social
    ring: posts/u1
    applied event
```

### Tradeoffs

This is a durable scheduler boundary, not immediate global consistency.
Long-running scheduling remains outside the hot DB loop.

## Docker Compose Files

Runnable Compose examples live under:

- [examples/compose/single-galaxy.compose.yml](../examples/compose/single-galaxy.compose.yml)
- [examples/compose/three-node-galaxy.compose.yml](../examples/compose/three-node-galaxy.compose.yml)
- [examples/compose/local-remote-universe.compose.yml](../examples/compose/local-remote-universe.compose.yml)

They build the local source tree into a small RocheDB runtime container and run
`roched` with explicit galaxy credentials. They are examples, not production
hardening guides.

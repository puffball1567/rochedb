# Universe Redundancy

`universe` is RocheDB's logical disaster-recovery boundary above galaxy and
cluster. A universe is made of independent lanes, and each lane is a server
group / cluster with its own failure domain.

- A `galaxy` isolates one logical data domain.
- A `cluster` serves one galaxy across nodes.
- A `universe` keeps recoverable copies of that galaxy across independent
  server groups.

The purpose is simple: keep recoverable copies in failure domains that do not
all fail together. Those domains can be regions, availability zones, racks,
accounts, storage classes, or separate server groups. AWS Tokyo and AWS Oregon
are one obvious example, but a universe is not defined by region. It is defined
by independent lanes.

## v0.2.0 Direction

Universe redundancy is a v0.2.0 design direction. The first practical primitive
should be mirrored recovery backup:

```sh
bin/rochecli universe-backup \
  --data=data/galaxy-a \
  --mirror=/backup/local/galaxy-a \
  --mirror=/mnt/remote/galaxy-a
```

Encrypted mirrors use the same encrypted backup format:

```sh
bin/rochecli universe-backup \
  --data=data/galaxy-a \
  --mirror=/backup/local/galaxy-a \
  --mirror=/mnt/remote/galaxy-a \
  --passphrase=change-me
```

The command should write a compact backup snapshot to every mirror and fail if
any mirror fails. This is closer to RAID-1 for recovery snapshots than to online
cluster replication.

## Recovery

Any successful mirror can be restored with the normal restore commands:

```sh
bin/rochecli restore --backup=/backup/local/galaxy-a --data=restored/galaxy-a
```

Encrypted mirror:

```sh
bin/rochecli restore-encrypted \
  --backup=/backup/local/galaxy-a \
  --data=restored/galaxy-a \
  --passphrase=change-me
```

## Cluster Repair vs Universe Recovery

Cluster repair handles data corruption inside one serving topology. Examples:

- one node has a damaged WAL;
- one node misses committed data;
- replicas disagree;
- a transaction apply was interrupted;
- handoff/forwarder state was incomplete;
- an application submitted a bad write that must be corrected by cluster-level
  validation, repair, or later compensating writes.

Universe recovery handles logical disaster recovery across independent lanes.
Examples:

- one lane's server group is unavailable;
- Tokyo region is unavailable;
- the primary cluster's disks are lost;
- a whole cluster has to be rebuilt elsewhere;
- operations needs to restore from a remote recovery lane.

Keeping the layers separate avoids coupling one galaxy's live write path to
every remote lane. It also keeps galaxy isolation clear: a universe can mirror
one galaxy without merging it with other galaxies.

## Parallel Universe Clusters

The long-term model is a set of independent lanes that hold the same logical
galaxy through separate failure domains. A lane does not have to map to a
region. It can be a region, an availability zone, a rack, a cloud account, a
storage class, or any server group that can fail independently.

For example, 40 servers can be split into four 10-node lanes:

```text
universe: production-a
  universe-lane-0: 10-node RocheDB cluster / server group
  universe-lane-1: 10-node RocheDB cluster / server group
  universe-lane-2: 10-node RocheDB cluster / server group
  universe-lane-3: 10-node RocheDB cluster / server group
```

Those 10 nodes do not have to live in the same region either. A single lane can
spread its nodes across regions, zones, racks, or providers if the latency and
failure model are acceptable. Universe only requires that lanes are meaningful
failure domains; it does not impose a physical placement shape.

The primary lane serves normal reads and writes. Other universe lanes receive
ordered recovery data asynchronously. This is similar to replication delay: the
source keeps its committed state until the remote lane acknowledges enough
recovery material.

`warp` is the right conceptual extension point for this. A future universe warp
lane can carry:

- committed transaction intents;
- compact snapshot manifests;
- WAL segment references;
- checksums and sequence ranges;
- mirror acknowledgements;
- retry / dead-letter state.

This keeps the primary cluster logic local while giving the universe layer a
durable queue for cross-cluster propagation.

## RAID-Like Modes

The useful analogy is RAID for recovery domains, not block-device RAID inside
one database process.

| Mode | Meaning | Use |
|---|---|---|
| Universe mirror | Copy the full compact snapshot or WAL segment to N lanes | Simple RAID-1-like recovery |
| Universe quorum | Accept recovery state after M of N lanes acknowledge | Survive one or more mirror outages |
| Universe parity | Store erasure-coded snapshot/WAL segments across lanes | RAID5/6-like storage efficiency |

The parity layer should apply to immutable recovery artifacts such as snapshots
and WAL segments. Live logical writes should still be ordered and replayable.
That avoids coupling transaction correctness to parity reconstruction.

This can make RocheDB more resilient than a single-lane deployment because a
whole cluster, disk set, rack, account, or region can fail without destroying
all recovery copies. Logical corruption and bad writes should be handled by
cluster-level validation, repair, retention, and compensating-write mechanisms.
Universe keeps recovery lanes available when one server group is lost.

## v0.2.0 Work Items

Universe work can add:

- mirror manifests with names, failure domains, and storage classes;
- verify commands that compare snapshot metadata across mirrors;
- restore priority rules;
- scheduled mirror jobs;
- universe warp lanes for asynchronous cross-cluster propagation;
- quorum acknowledgement policy;
- object storage adapters such as S3 and GCS;
- immutable / versioned mirror retention;
- point-in-time recovery using WAL segments;
- erasure-coded parity for immutable recovery artifacts;
- optional online cross-cluster mirror streams.

The design rule is conservative: recovery copies must make data loss less
likely without making the primary write path fragile.

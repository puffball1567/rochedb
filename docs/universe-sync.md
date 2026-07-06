# Universe Sync

Universe sync is RocheDB's eventual-convergence boundary for copying selected
writes from one RocheDB universe into another. It is designed for AI datasets,
prompt/context stores, regional read models, and other workloads where local
reads should stay fast while remote convergence may happen slightly later.

It is not a strict global transaction protocol. If a workload requires immediate
cross-region finality for every write, keep that workload in a stronger
transactional system or isolate it into a small RocheDB deployment with stricter
operational controls.

## Model

Universe sync uses a source outbox:

1. `putSynced` stores the local document and appends a WAL-backed sync event.
2. The event remains pending until a target accepts it.
3. A target applies the event with `UAPPLY`.
4. The source marks the event acknowledged.
5. Acknowledged events may be pruned after operators confirm the target state.

Each event carries an `eventKey`. Targets record applied keys, so replaying the
same event is idempotent and returns `SKIPPED` instead of duplicating data.

## Local Data-Dir Sync

For offline or batch movement between two data directories:

```bash
src/rochecli universe-sync --data=/var/lib/roche/source --target=/var/lib/roche/target
```

Use `--prune-acked` only after the target state is considered durable enough for
your recovery policy.

## Remote Peer Sync

For a running cluster:

```bash
src/rochecli universe-sync \
  --data=/var/lib/roche/source \
  --peers=127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613 \
  --username=admin \
  --password=secret \
  --secret-key=shared-secret \
  --galaxy=main
```

The remote server routes the event to the owner node for the target ring. This
keeps the client simple and avoids requiring the source process to know the
target cluster's internal placement details.

## Delayed And Latest-Only Writes

Some workloads only need the latest value for a logical key. Others need a short
delay window so events can be applied in timestamp order. RocheDB supports both
patterns at the outbox level:

- latest-only pending coalescing keeps only the newest pending event for a key.
- delayed apply windows hold events until their timestamp is ready.

These policies are intended for profiles, context summaries, feature snapshots,
and other data where eventual convergence is acceptable. Append-only domains
such as comments can store timestamped documents and sort at read time.

## Status

Source outbox status:

```bash
src/rochecli universe-status --data=/var/lib/roche/source
```

Remote apply status:

```bash
src/rochecli universe-status --peers=127.0.0.1:17611,127.0.0.1:17612
```

Metrics format:

```bash
src/rochecli universe-status --peers=127.0.0.1:17611,127.0.0.1:17612 --metrics
```

Remote status reports both durable applied event keys and process-local apply
counters:

- `universeSyncPending`
- `universeSyncApplied`
- `universeApplyApplied`
- `universeApplySkipped`
- `universeApplyErrors`
- `universeApplyForwarded`
- `universeApplyLastOk`
- `universeApplyLastError`

The `universeApply*` counters are operational process counters. They are useful
for dashboards and alerts, but they are not a durable audit log.

## Failure Behavior

If the target is down, the source outbox keeps the event pending. A later
`universe-sync` run retries the same event. If the target already applied it,
the target returns `SKIPPED` through idempotency and the source can acknowledge
the event safely.

This gives RocheDB a durable scheduler boundary without introducing a global
coordinator. The tradeoff is that remote visibility is eventual, not immediate.


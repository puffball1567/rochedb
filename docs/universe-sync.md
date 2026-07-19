# Universe Sync

Universe sync is OrbeliasDB's eventual-convergence boundary for copying selected
writes from one OrbeliasDB universe into another. It is designed for AI datasets,
prompt/context stores, regional read models, and other workloads where local
reads should stay fast while remote convergence may happen slightly later.

It is not a strict global transaction protocol. If a workload requires immediate
cross-region finality for every write, keep that workload in a stronger
transactional system or isolate it into a small OrbeliasDB deployment with stricter
operational controls.

## Model

Universe sync uses a source outbox:

1. `putSynced` stores the local document and appends a WAL-backed sync event in
   one Store transaction.
2. The event remains pending until a target accepts it.
3. A target applies the event with `UAPPLY`.
4. The source marks the event acknowledged.
5. Acknowledged events may be pruned after operators confirm the target state.

Each event carries an `eventKey`. Targets record applied keys, so replaying the
same event is idempotent and returns `SKIPPED` instead of duplicating data.
The applied-key set is bounded by a retention policy. Older applied keys are
pruned after the configured retention count, and the prune is WAL-recorded so
restart and compact keep the same idempotency window.

Source event ids are monotonic across pruning. OrbeliasDB persists the next source
outbox sequence separately from the currently live events, so pruning every
acknowledged event and restarting the source does not reuse old ids.

## Local Data-Dir Sync

For offline or batch movement between two data directories:

```bash
orbelias universe-sync --data=/var/lib/orbelias/source --target=/var/lib/orbelias/target
```

Use `--prune-acked` only after the target state is considered durable enough for
your recovery policy.

## Remote Peer Sync

For a running cluster:

```bash
orbelias universe-sync \
  --data=/var/lib/orbelias/source \
  --peers=127.0.0.1:17611,127.0.0.1:17612,127.0.0.1:17613 \
  --user=admin \
  --password-file=/run/secrets/orbelias_password \
  --secret-key-file=/run/secrets/orbelias_secret_key \
  --galaxy=main
```

The remote server routes the event to the owner node for the target ring. This
keeps the client simple and avoids requiring the source process to know the
target cluster's internal placement details.

## Delayed And Latest-Only Writes

Some workloads only need the latest value for a logical key. Others need a short
delay window so events can be applied in timestamp order. OrbeliasDB supports both
patterns at the outbox level:

- latest-only pending coalescing keeps only the newest pending event for a key.
- delayed apply windows hold events until their timestamp is ready.

For `putSynced`, latest-only replacement is committed together with the local
write. The old pending event delete and the new pending event are stored under
the same transaction commit marker.

These policies are intended for profiles, context summaries, feature snapshots,
and other data where eventual convergence is acceptable. Append-only domains
such as comments can store timestamped documents and sort at read time.

Remote delivery uses the same boundary. A source event may carry `applyAfter`.
When the target receives the event too early, `UAPPLY` returns `DELAYED`; the
source does not acknowledge the event, so the next sync run can retry it.
`DELAYED` is not counted as a failed attempt.

Delivery failures are tracked on the source event:

- `attempts`
- `maxAttempts`
- `retryAt`
- `deadLetter`
- `error`

When a delivery attempt throws or the remote target cannot be reached, OrbeliasDB
increments `attempts`, stores a backoff `retryAt`, and leaves the event pending.
After the retry budget is exhausted, the event becomes `deadLetter=true`. Dead
letters are not acknowledged and are not pruned by `--prune-acked`; an operator
or future scheduler adapter must inspect or requeue them explicitly.

## Status

Source outbox status:

```bash
orbelias universe-status --data=/var/lib/orbelias/source
```

Remote apply status:

```bash
orbelias universe-status --peers=127.0.0.1:17611,127.0.0.1:17612
```

Metrics format:

```bash
orbelias universe-status --peers=127.0.0.1:17611,127.0.0.1:17612 --metrics
```

Remote status reports both durable applied event keys and process-local apply
counters:

- `universeSyncPending`
- `universeSyncRetrying`
- `universeSyncDeadLetter`
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
`universe-sync` run retries the same event after the stored `retryAt` boundary.
If the target already applied it, the target returns `SKIPPED` through
idempotency and the source can acknowledge the event safely. If the retry budget
is exhausted, the event remains in the outbox as a dead letter instead of being
silently dropped.

This gives OrbeliasDB a durable scheduler boundary without introducing a global
coordinator. The tradeoff is that remote visibility is eventual, not immediate.

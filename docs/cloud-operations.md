# Cloud Operations Metrics

RocheDB v0.1.0 exposes lightweight node metrics through the existing wire
protocol and CLI:

```sh
bin/rochecli metrics --peers=127.0.0.1:7301,127.0.0.1:7302,127.0.0.1:7303
```

This is intentionally not a Prometheus, OpenMetrics, Datadog, or CloudWatch
exporter yet. The output is a stable key/value line that can be scraped by a
sidecar, init script, cron job, or managed-agent integration on AWS, GCP, and
similar platforms.

## Metrics

| Metric | Meaning | Operational use |
|---|---|---|
| `node` | Node index in the static peer list | Identify the reporting node |
| `uptimeSec` | Process uptime in seconds | Restart detection |
| `requests` | Frames processed by the node | Traffic baseline and load |
| `errors` | Error responses emitted by the node | Alert on protocol, auth, or internal failures |
| `authFailures` | Failed authentication attempts | Credential abuse or misconfiguration signal |
| `authzDenied` | Authorization denials | Role/ring-prefix policy mismatch or probing |
| `connectionsAccepted` | Total accepted TCP connections | Connection churn baseline |
| `activeConnections` | Current open TCP connections | Client pressure and leak detection |
| `items` | Stored live particles/documents on the node | Capacity and skew monitoring |
| `rings` | Known ring metadata count | Routing/domain growth |
| `forwarders` | Active handoff forwarders | Orbital handoff pressure |
| `walBytes` | Current WAL file size in bytes | Disk capacity and compaction trigger |
| `warpJobs` | Persisted warp jobs | Delayed update backlog |
| `persistent` | `1` when running with a data directory | Deployment sanity check |
| `durabilityStrong` | `1` when fsync durability is enabled | Durability policy sanity check |
| `clusterTxCommitted` | Committed cluster transaction intents | Transaction landing throughput |
| `clusterTxApplied` | Applied cluster transaction intents | Apply progress |
| `clusterTxPending` | Committed but unapplied cluster transaction intents | Retry backlog / owner failure signal |
| `clumps` | Field-state clump count | Query/index state growth |

## Suggested Alerts

Start with conservative alerts:

- `clusterTxPending` remains above `0` for longer than the expected owner
  restart/retry window.
- `errors` increases quickly compared with `requests`.
- `authFailures` or `authzDenied` increase unexpectedly.
- `walBytes` approaches the disk budget or grows much faster than `items`.
- `activeConnections` rises without returning to the normal range.
- `uptimeSec` resets outside planned maintenance.

## Cloud Mapping

On AWS, these values can be pushed as CloudWatch custom metrics by a small
sidecar or scheduled task. On GCP, use an Ops Agent custom script or a small
collector that converts the key/value response into Cloud Monitoring metrics.
Datadog can ingest the same values through a custom check or by converting them
to OpenMetrics in a sidecar.

RocheDB does not require cloud-specific APIs in the core. The core exposes the
operational facts; deployment tooling decides how to ship them.

## Post-v0.1 Exporters

Prometheus / OpenMetrics output and a Datadog-friendly collector are v0.2+
candidates. They should live outside the core server loop so RocheDB does not
take a dependency on any single cloud or observability vendor.

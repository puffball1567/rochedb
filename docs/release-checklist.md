# RocheDB Release Checklist

This is the canonical release checklist for the public RocheDB repository.

## v0.1.0 Positioning

Release v0.1.0 as a technical preview / research OSS release.

Recommended wording:

```text
RocheDB v0.1.0 Technical Preview
A ring/galaxy-oriented document and vector database prototype focused on
reducing working-set size for retrieval-heavy systems.
```

Avoid claiming that RocheDB is generally faster than Redis, PostgreSQL, or
Apache Arrow. The current defensible claim is narrower:

```text
Local reads are being moved toward existing database speed bands, while
RAG-style synthetic benchmarks show reduced scanned candidates and token input
under the documented conditions.
```

## Required Before v0.1.0

| Area | Required Item | Status |
|---|---|---|
| Core tests | `scripts/test_core.sh` passes | Done |
| WAL recovery | Torn-tail, invalid length, invalid vector dim, partial transaction tests pass | Done |
| Warp belt | WAL persistence, reopen recovery, ack cleanup, idempotent patch behavior | Done |
| Cluster smoke | tx / failure retry / authz / RBAC / wire fuzz smoke scripts pass locally | Done |
| FAISS bridge | `rochecli doctor` and FAISS bridge smoke are documented and reproducible | Done |
| Drivers | Driver status table is accurate and does not overclaim package publication | Done |
| Bench docs | Benchmark conditions, limitations, Redis/PostgreSQL wording, and environment are consistent | Done |
| AI/RAG case study | Generated JSONL corpus is imported and measured with global / routed / wrong-ring retrieval | Done |
| Security docs | Threat model and third-party notices are present | Done |
| License docs | Core license and third-party dependency licenses are clear | Done |
| Generated files | Test binaries and temporary outputs are not included in release artifacts | Done; build/test binaries removed, ignored local FAISS bridge may remain for doctor |

## Recommended Before v0.1.0

| Area | Item |
|---|---|
| Release notes | Done: `CHANGELOG.md` and `docs/github-release-v0.1.0.md` |
| Docker | Done: Docker-backed PHP / Swift / Kotlin smoke passed locally |
| Cluster | Done: local 3-node smoke scripts passed locally |
| Docs | Done: README links to status, benchmark, threat model, driver roadmap, and release draft |
| Examples | Done: cluster demo passed locally; core tests cover embedded usage |
| AI/RAG demo | Done: `examples/ai_rag_case_study.sh` passed locally |
| Package metadata | Done: `rochedb.nimble` version / description / license checked |

## Explicitly Not Required For v0.1.0

These are important, but should not block the first technical preview:

- TLS for public-network deployments
- dynamic cluster membership
- cluster coordinator redundancy
- multi-VM / multi-AZ benchmark
- WASM browser build
- FlowBrigade / FlowLogbook adapter
- enterprise plugin features
- package publication to npm / PyPI / Cargo / Composer / NuGet / Maven
- online universe replication / object-storage mirror adapters / PITR
- cluster repair protocol: checksums, scrub, replica comparison, and repair metrics

## Post-v0.1 Direction

The post-v0.1 roadmap should focus on integration and operational maturity.
The items below are candidates for v0.2 and later releases, not a promise that
all of them fit into v0.2.0:

- `rochedb-flow` adapter
- FlowBrigade-backed retry / backoff / lock / rate limit for warp belt
- FlowLogbook-compatible warp attempt and ack history
- server-side warp scheduler
- browser / WASM local-state boundary
- stronger cluster operational stories
- package publication workflows
- Prometheus / OpenMetrics and Datadog metrics adapters

## Final Release Gate

Before tagging:

1. Run core tests.
2. Run local cluster smoke scripts.
3. Run selected Docker-backed driver smoke tests.
4. Review benchmark wording.
5. Review license and third-party notices.
6. Remove generated binaries and temporary artifacts.
7. Confirm README and status docs describe v0.1.0 as technical preview.

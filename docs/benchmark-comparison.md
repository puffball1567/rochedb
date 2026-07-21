---
layout: page
title: Benchmark Comparison Tables
---

# Benchmark Comparison Tables

This page keeps the benchmark numbers in comparison-friendly tables. It is a
companion to [Benchmark Notes](koutendb-bench.md), which contains the full
conditions, reproduction notes, and interpretation.

These are local measurements, not universal performance claims.

## PostgreSQL Reference

Environment summary: same machine as KoutenDB, AMD Ryzen 5 5600H, Linux 6.8,
Nim 2.2.10, PostgreSQL 14.23, local TCP, single client, 100-byte payload where
applicable. Measured on 2026-07-21.

Reproduction helper: `N=10000 examples/postgres_bench.sh`.
The helper creates a fresh temporary KoutenDB data directory and a fresh
temporary PostgreSQL cluster for each run, then removes them on exit.

Docker reproduction helper: `N=10000 examples/postgres_docker_bench.sh`.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| KoutenDB | single-key read | 53.5 | Three `koutend` nodes, persistence enabled |
| KoutenDB | single-row write | 61.1 | Three `koutend` nodes, persistence enabled |
| KoutenDB | query projection | 61.1 | Server-side JSON projection |
| KoutenDB | strong-durability write | not measured | `durStrong` / `--durability=strong` was not part of this comparison |
| PostgreSQL 14.23 | primary-key `SELECT` | 86 | `pgbench -M prepared`, 11,570 tps |
| PostgreSQL 14.23 | single-row write, `synchronous_commit=off` | 104 | `pgbench -M prepared`, 9,621 tps |
| PostgreSQL 14.23 | single-row write, `synchronous_commit=on` | 1941 | `pgbench -M prepared`, 515 tps |

## PostgreSQL Docker Reference

Environment summary: same host as KoutenDB, Docker `overlay2`, KoutenDB image
built from `examples/compose/Dockerfile`, PostgreSQL image `postgres:14`, same
Docker network, single client, 100-byte payload, `n=10000`. Data directories
are bind-mounted from a temporary helper directory during the helper run.
Measured on 2026-07-15.

Reproduction helper: `N=10000 examples/postgres_docker_bench.sh`.
The helper starts fresh KoutenDB and PostgreSQL containers on a fresh Docker
network and removes the containers, network, and temporary data directory on
exit.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| KoutenDB Docker | single-key read | 61.3 | Three `koutend` containers |
| KoutenDB Docker | single-row write | 103.6 | Three `koutend` containers |
| KoutenDB Docker | query projection | 65.3 | Server-side JSON projection |
| PostgreSQL 14 Docker | primary-key `SELECT` | 103 | `pgbench -M prepared`, 9,669 tps |
| PostgreSQL 14 Docker | single-row write, `synchronous_commit=off` | 149 | `pgbench -M prepared`, 6,720 tps |
| PostgreSQL 14 Docker | single-row write, `synchronous_commit=on` | 1162 | `pgbench -M prepared`, 860 tps |

## User Bundle PostgreSQL Reference

Environment summary: same machine as KoutenDB, AMD Ryzen 5 5600H, Linux 6.8,
Nim 2.2.10, PostgreSQL 14.23, local temporary PostgreSQL cluster,
single client, prepared statements. Measured on 2026-07-21.

Reproduction helper:
`N=100000 READS=500 examples/user_bundle_postgres_bench.sh`.

This benchmark is not a single primary-key lookup. It models a user-detail
bundle where each user has profile, addresses, career entries, preferences, and
orders. KoutenDB stores the records under coordinate-local rings such as
`users/<id>/profile` and reads the bundle with a narrowed stellar read.
PostgreSQL stores the same logical data in normalized indexed tables.

| Users | Logical records | Group | Query shape | read latency us |
|---:|---:|---|---|---:|
| 1,000 | 20,000 | KoutenDB | `users/<id>/*` stellar depth read | 213.248 |
| 1,000 | 20,000 | PostgreSQL 14.23 | five indexed `SELECT` statements | 424 |
| 1,000 | 20,000 | PostgreSQL 14.23 | one JSON aggregate query | 246 |
| 10,000 | 200,000 | KoutenDB | `users/<id>/*` stellar depth read | 202.668 |
| 10,000 | 200,000 | PostgreSQL 14.23 | five indexed `SELECT` statements | 442 |
| 10,000 | 200,000 | PostgreSQL 14.23 | one JSON aggregate query | 257 |
| 100,000 | 2,000,000 | KoutenDB | `users/<id>/*` stellar depth read | 205.799 |
| 100,000 | 2,000,000 | PostgreSQL 14.23 | five indexed `SELECT` statements | 407 |
| 100,000 | 2,000,000 | PostgreSQL 14.23 | one JSON aggregate query | 240 |

The KoutenDB read path stayed roughly flat here because the query starts from
the user coordinate and only visits the requested subrings. The helper also
prints insertion and pack timings; the 100,000-user run inserted 2,000,000
logical records at `33.442073 us/record`, which makes bulk load and many-ring
metadata creation clear follow-up optimization targets.

### Heterogeneous Subring Bundle

This benchmark is closer to a real application detail endpoint: each related
collection has its own limit and sort order. KoutenDB reads a `users/<id>/*`
stellar neighborhood with per-subring options:

```sh
kouten get --ring=users/<id> \
  --subring=profile,addresses,career,preferences,orders,notifications \
  --subring-limit=profile:1,addresses:3,career:2,preferences:1,orders:10,notifications:5 \
  --subring-rsort=orders:time,notifications:time
```

PostgreSQL stores the same logical data in normalized indexed tables. The
comparison includes both multiple indexed `SELECT` statements and a single
`jsonb_build_object` / `jsonb_agg` query with limited subqueries.

Reproduction helper:

```sh
N=10000 READS=1000 examples/subring_bundle_postgres_bench.sh
```

Measured on the same local machine as the other local PostgreSQL benchmarks:
AMD Ryzen 5 5600H, Linux 6.8, Nim 2.2.10, PostgreSQL 14.23, local temporary
PostgreSQL cluster, KoutenDB disk-backed mode, fresh temporary data directories,
single client, `N=10000`, `READS=1000`. Measured on 2026-07-21.

| Users | Logical records | Group | Query shape | Returned records | read latency us |
|---:|---:|---|---|---:|---:|
| 10,000 | 1,050,000 | KoutenDB | `users/<id>/*` stellar read with per-subring limits/sorts | 22 across 6 rings | 196.859 |
| 10,000 | 1,050,000 | PostgreSQL 14.23 | six indexed `SELECT` statements | 22 | 515 |
| 10,000 | 1,050,000 | PostgreSQL 14.23 | one JSON aggregate query over indexed limited subqueries | 1 JSON bundle | 236 |

This is not a universal PostgreSQL claim. It is a specific related-data bundle
shape where KoutenDB can express the access pattern directly as bounded nearby
subrings. PostgreSQL can express the same result with advanced SQL, but the
query shape is no longer a plain join.

## Redis Reference

Environment summary: same machine as KoutenDB, AMD Ryzen 5 5600H, Linux 6.8,
Nim 2.2.10, local Redis 6.0.16, one local `koutend`, buffered durability with
a fresh temporary data directory,
local TCP, single client, 100-byte payload, `n=1000`, Redis pipeline batch size
256. Measured on 2026-07-21.

Local reproduction helper: `N=1000 examples/redis_local_bench.sh`.
The helper starts KoutenDB with a fresh temporary data directory and removes it
on exit. Redis local uses the configured Redis endpoint; the benchmark writes
under a unique `koutendb:bench:<timestamp>:` prefix and deletes those keys
before exit.

Docker reproduction helper: `N=1000 examples/redis_docker_bench.sh`.
The Docker helper starts fresh Redis and KoutenDB containers on a fresh Docker
network and removes them on exit.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| KoutenDB | embedded get | 0.09 | In-process hot path; no TCP |
| KoutenDB | TCP GET | 52.88 | One request / one response |
| KoutenDB | TCP BGET | 1.81 | Batch read; comparable axis to Redis pipeline |
| Redis 6.0.16 | TCP GET | 44.93 | Non-pipelined local Redis |
| Redis 6.0.16 | pipeline GET | 3.55 | Batch size 256 |

Docker-Docker measurements under the same benchmark shape:

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| KoutenDB Docker | embedded get | 0.04 | In-process hot path inside the benchmark container |
| KoutenDB Docker | TCP GET | 55.78 | One request / one response across Docker network |
| KoutenDB Docker | TCP BGET | 1.71 | Batch read; comparable axis to Redis pipeline |
| Redis 7 Docker | TCP GET | 48.74 | Non-pipelined Redis on the same Docker network |
| Redis 7 Docker | pipeline GET | 2.06 | Batch size 256 |

## Working-Set And Token Reduction

| Benchmark | Setup | Result |
|---|---|---|
| Working-set | 100 rings / 10k docs | scanned/query `10000 -> 100` |
| Memory-pressure | 100 rings / 100k docs / 512-byte payload | candidate memory/query `93.079 MiB -> 0.931 MiB` |
| Synthetic RAG | fixed recall | recall `1.000`, scanned/query `8000 -> 1000`, tokens/query `3955 -> 657` |
| AI/RAG case study | generated JSONL, 400 docs / 6 rings | recall `1.000`, scanned/query `400 -> 40`, tokens/query `615.2 -> 231.6` |

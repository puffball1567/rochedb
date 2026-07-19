---
layout: page
title: Benchmark Comparison Tables
---

# Benchmark Comparison Tables

This page keeps the benchmark numbers in comparison-friendly tables. It is a
companion to [Benchmark Notes](orbeliasdb-bench.md), which contains the full
conditions, reproduction notes, and interpretation.

These are local measurements, not universal performance claims.

## PostgreSQL Reference

Environment summary: same machine as OrbeliasDB, AMD Ryzen 5 5600H, Linux 6.8,
Nim 2.2.10, PostgreSQL 14.23, local TCP, single client, 100-byte payload where
applicable. Measured on 2026-07-15.

Reproduction helper: `N=10000 examples/postgres_bench.sh`.
The helper creates a fresh temporary OrbeliasDB data directory and a fresh
temporary PostgreSQL cluster for each run, then removes them on exit.

Docker reproduction helper: `N=10000 examples/postgres_docker_bench.sh`.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| OrbeliasDB | single-key read | 46.8 | Three `orbeliasd` nodes, persistence enabled |
| OrbeliasDB | single-row write | 48.8 | Three `orbeliasd` nodes, persistence enabled |
| OrbeliasDB | query projection | 53.3 | Server-side JSON projection |
| OrbeliasDB | strong-durability write | not measured | `durStrong` / `--durability=strong` was not part of this comparison |
| PostgreSQL 14.23 | primary-key `SELECT` | 68 | `pgbench -M prepared`, 14,659 tps |
| PostgreSQL 14.23 | single-row write, `synchronous_commit=off` | 80 | `pgbench -M prepared`, 12,433 tps |
| PostgreSQL 14.23 | single-row write, `synchronous_commit=on` | 1935 | `pgbench -M prepared`, 517 tps |

## PostgreSQL Docker Reference

Environment summary: same host as OrbeliasDB, Docker `overlay2`, OrbeliasDB image
built from `examples/compose/Dockerfile`, PostgreSQL image `postgres:14`, same
Docker network, single client, 100-byte payload, `n=10000`. Data directories
are bind-mounted from a temporary helper directory during the helper run.
Measured on 2026-07-15.

Reproduction helper: `N=10000 examples/postgres_docker_bench.sh`.
The helper starts fresh OrbeliasDB and PostgreSQL containers on a fresh Docker
network and removes the containers, network, and temporary data directory on
exit.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| OrbeliasDB Docker | single-key read | 61.3 | Three `orbeliasd` containers |
| OrbeliasDB Docker | single-row write | 103.6 | Three `orbeliasd` containers |
| OrbeliasDB Docker | query projection | 65.3 | Server-side JSON projection |
| PostgreSQL 14 Docker | primary-key `SELECT` | 103 | `pgbench -M prepared`, 9,669 tps |
| PostgreSQL 14 Docker | single-row write, `synchronous_commit=off` | 149 | `pgbench -M prepared`, 6,720 tps |
| PostgreSQL 14 Docker | single-row write, `synchronous_commit=on` | 1162 | `pgbench -M prepared`, 860 tps |

## Redis Reference

Environment summary: same machine as OrbeliasDB, AMD Ryzen 5 5600H, Linux 6.8,
Nim 2.2.10, local Redis 6.0.16, one local `orbeliasd`, persistence disabled,
local TCP, single client, 100-byte payload, `n=1000`, Redis pipeline batch size
256. Measured on 2026-07-15.

Local reproduction helper: `N=1000 examples/redis_local_bench.sh`.
The helper starts OrbeliasDB with a fresh temporary data directory and removes it on
exit. Redis local uses the existing Redis server, but the benchmark writes under
a unique `orbeliasdb:bench:<timestamp>:` prefix and deletes those keys before exit.

Docker reproduction helper: `N=1000 examples/redis_docker_bench.sh`.
The Docker helper starts fresh Redis and OrbeliasDB containers on a fresh Docker
network and removes them on exit.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| OrbeliasDB | embedded get | 0.03 | In-process hot path; no TCP |
| OrbeliasDB | TCP GET | 45.26 | One request / one response |
| OrbeliasDB | TCP BGET | 1.48 | Batch read; comparable axis to Redis pipeline |
| Redis 6.0.16 | TCP GET | 42.85 | Non-pipelined local Redis |
| Redis 6.0.16 | pipeline GET | 3.53 | Batch size 256 |

Docker-Docker measurements under the same benchmark shape:

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| OrbeliasDB Docker | embedded get | 0.04 | In-process hot path inside the benchmark container |
| OrbeliasDB Docker | TCP GET | 55.78 | One request / one response across Docker network |
| OrbeliasDB Docker | TCP BGET | 1.71 | Batch read; comparable axis to Redis pipeline |
| Redis 7 Docker | TCP GET | 48.74 | Non-pipelined Redis on the same Docker network |
| Redis 7 Docker | pipeline GET | 2.06 | Batch size 256 |

## Working-Set And Token Reduction

| Benchmark | Setup | Result |
|---|---|---|
| Working-set | 100 rings / 10k docs | scanned/query `10000 -> 100` |
| Memory-pressure | 100 rings / 100k docs / 512-byte payload | candidate memory/query `93.079 MiB -> 0.931 MiB` |
| Synthetic RAG | fixed recall | recall `1.000`, scanned/query `8000 -> 1000`, tokens/query `3955 -> 657` |
| AI/RAG case study | generated JSONL, 400 docs / 6 rings | recall `1.000`, scanned/query `400 -> 40`, tokens/query `615.2 -> 231.6` |

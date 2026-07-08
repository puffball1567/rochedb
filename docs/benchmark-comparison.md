---
layout: page
title: Benchmark Comparison Tables
---

# Benchmark Comparison Tables

This page keeps the benchmark numbers in comparison-friendly tables. It is a
companion to [Benchmark Notes](rochedb-bench.md), which contains the full
conditions, reproduction notes, and interpretation.

These are local measurements, not universal performance claims.

## PostgreSQL Reference

Environment summary: same machine as RocheDB, AMD Ryzen 5 5600H, Linux 6.8,
Nim 2.2.10, PostgreSQL 14.23, local TCP, single client, 100-byte payload where
applicable.

Reproduction helper: `N=10000 examples/postgres_bench.sh`.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| RocheDB | single-key read | 45.2-46.5 | Three `roched` nodes, persistence enabled |
| RocheDB | single-row write | 48.5-49.0 | Three `roched` nodes, persistence enabled |
| RocheDB | strong-durability write | not measured | `durStrong` / `--durability=strong` was not part of this comparison |
| PostgreSQL 14 | primary-key `SELECT` | 75 | `pgbench -M prepared`, 13.3k tps |
| PostgreSQL 14 | single-row write, `synchronous_commit=off` | 80 | `pgbench -M prepared`, 12.5k tps |
| PostgreSQL 14 | single-row write, `synchronous_commit=on` | 1961 | `pgbench -M prepared`, 510 tps |

## Redis Reference

Environment summary: same machine as RocheDB, AMD Ryzen 5 5600H, Linux 6.8,
Nim 2.2.10, local Redis 6.0.16, one local `roched`, persistence disabled,
local TCP, single client, 100-byte payload, `n=1000`, Redis pipeline batch size
256.

Local reproduction helper: `N=1000 examples/redis_local_bench.sh`.

Docker reproduction helper: `N=1000 examples/redis_docker_bench.sh`.

| Group | Operation | us/op | Notes |
|---|---|---:|---|
| RocheDB | embedded get | 0.03 | In-process hot path; no TCP |
| RocheDB | TCP GET | 44.87 | One request / one response |
| RocheDB | TCP BGET | 1.47 | Batch read; comparable axis to Redis pipeline |
| Redis 6.0.16 | TCP GET | 41.23 | Non-pipelined local Redis |
| Redis 6.0.16 | pipeline GET | 3.68 | Batch size 256 |

## Working-Set And Token Reduction

| Benchmark | Setup | Result |
|---|---|---|
| Working-set | 100 rings / 10k docs | scanned/query `10000 -> 100` |
| Memory-pressure | 100 rings / 100k docs / 512-byte payload | candidate memory/query `93.079 MiB -> 0.931 MiB` |
| Synthetic RAG | fixed recall | recall `1.000`, scanned/query `8000 -> 1000`, tokens/query `3960 -> 657.8` |
| AI/RAG case study | generated JSONL, 400 docs / 6 rings | recall `1.000`, scanned/query `400 -> 40`, tokens/query `615.2 -> 231.6` |

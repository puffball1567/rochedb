# Effect Validation

This document tracks small, reproducible KoutenDB effect-validation demos.
These are generated local workloads, not universal performance claims.

The goal is to make KoutenDB's main claim testable:

- reduce the candidate set that must be scanned;
- reduce estimated downstream context tokens;
- produce a compact prompt before any LLM is called;
- keep the model choice optional and explicit.

## Single Demo

```sh
examples/effect_validation_demo.sh
```

The demo generates a deterministic JSONL corpus, imports it into KoutenDB, and
compares:

- global retrieval across the whole generated corpus;
- ring-routed retrieval scoped to `docs/japan`.

Representative local output:

| docs | global scanned | routed scanned | global tokens | routed tokens |
| ---: | ---: | ---: | ---: | ---: |
| 168 | 168 | 24 | 692 | 260 |

This means the demo reduced scanned records by `85.7%` and estimated tokens by
`62.4%` before sending anything to an LLM.

## Matrix Demo

```sh
examples/effect_validation_matrix.sh
KOUTEN_EFFECT_LARGE=1 examples/effect_validation_matrix.sh
KOUTEN_EFFECT_QUICK=1 examples/effect_validation_matrix.sh
```

This matrix is a manual validation path. It is intentionally not part of the
default CI smoke suite because the default and large cases are meant to create
millions of generated records.

The matrix uses several generated workload shapes:

- `small-balanced`: small corpus with one useful ring and unrelated rings;
- `near-distractors`: adds near-topic distractors to avoid a trivial clean split;
- `medium-noisy`: adds a larger unrelated background corpus;
- `large-noisy`: optional larger generated case enabled by `KOUTEN_EFFECT_LARGE=1`.

By default, the matrix uses `KOUTEN_EFFECT_SCALE=1000`, which reaches
13,500,000 documents in the standard run. `KOUTEN_EFFECT_LARGE=1` adds a
98,000,000-document generated stress case. Use `KOUTEN_EFFECT_QUICK=1` for the
smaller fast matrix, or set `KOUTEN_EFFECT_SCALE=N` explicitly.

Bulk load uses chunked commits. The default matrix uses
`KOUTEN_EFFECT_BATCH_SIZE=10000`; set it explicitly when comparing import
behavior:

```sh
KOUTEN_EFFECT_SCALE=1000 KOUTEN_EFFECT_BATCH_SIZE=10000 examples/effect_validation_matrix.sh
```

The current matrix path uses disk-backed storage by default
(`KOUTEN_EFFECT_DISK_BACKED=1`). Set `KOUTEN_EFFECT_DISK_BACKED=0` only when
you intentionally want to compare the legacy in-memory validation path.

Quick local sanity result from this repository state:

| case | docs | global budget | routed budget | set latency us | set us/record | pack latency us | scanned | tokens | retrieve latency us | scanned reduction | token reduction | prompt bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small-balanced | 168 | 8 | 3 | 2402.263 | 14.299185 | 9400.976 | 168 -> 24 | 692 -> 260 | 382.484 -> 59.650 | 85.714% | 62.428% | 1356 |
| near-distractors | 1860 | 20 | 5 | 26948.886 | 14.488648 | 102680.060 | 1860 -> 120 | 1730 -> 433 | 3388.369 -> 233.430 | 93.548% | 74.971% | 2064 |
| medium-noisy | 13500 | 30 | 8 | 177783.235 | 13.169129 | 681991.471 | 13500 -> 500 | 2595 -> 692 | 23756.021 -> 852.418 | 96.296% | 73.333% | 3124 |

Larger local validation with `KOUTEN_EFFECT_SCALE=100` and
`KOUTEN_EFFECT_BATCH_SIZE=10000`:

| case | docs | global budget | routed budget | set latency us | set us/record | pack latency us | scanned | tokens | retrieve latency us | scanned reduction | token reduction | prompt bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small-balanced | 16800 | 8 | 3 | 231157.641 | 13.759383 | 848768.915 | 16800 -> 2400 | 692 -> 260 | 28377.546 -> 4254.966 | 85.714% | 62.428% | 1360 |
| near-distractors | 186000 | 20 | 5 | 2523403.771 | 13.566687 | 9585530.665 | 186000 -> 12000 | 1730 -> 433 | 348492.042 -> 22159.867 | 93.548% | 74.971% | 2068 |
| medium-noisy | 1350000 | 30 | 8 | 17674021.261 | 13.091868 | 68635114.386 | 1350000 -> 50000 | 2595 -> 692 | 2588003.358 -> 92612.321 | 96.296% | 73.333% | 3128 |

The disk-backed path now separates two costs:

- `set latency`: normal JSONL import into the WAL-backed store;
- `pack latency`: an explicit physical-layout step that builds ring-local
  segment files for faster reads.

The WAL remains the source of truth. Ring segment files are rebuildable read
layout, similar in operational role to a compaction or optimize step. They are
not required for correctness.

Earlier scale-1000 WAL-baseline validation also completed on this machine with
the disk-backed matrix path. That pre-segment run is retained here as a stress
baseline, not as the current optimized read result:

| case | docs | global budget | routed budget | set latency us | set us/record | scanned | tokens | retrieve latency us | scanned reduction | token reduction | prompt bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small-balanced | 168000 | 8 | 3 | 2269360.968 | 13.508101 | 168000 -> 24000 | 692 -> 260 | 951587.552 -> 146019.973 | 85.714% | 62.428% | 1362 |
| near-distractors | 1860000 | 20 | 5 | 24689153.892 | 13.273739 | 1860000 -> 120000 | 1730 -> 433 | 10530762.520 -> 732946.083 | 93.548% | 74.971% | 2070 |
| medium-noisy | 13500000 | 30 | 8 | 184747113.507 | 13.684971 | 13500000 -> 500000 | 2595 -> 692 | 81464731.931 -> 3228825.983 | 96.296% | 73.333% | 3130 |

The scale-1000 stress baseline showed that the generated 13.5M-record case
completed without the previous OOM kill. The current segment-pack path should be
used for optimized disk-backed read measurements.

The important part is not that these generated numbers are universal. They show
how to test the effect: compare broad retrieval with placement-aware retrieval,
then report import latency, scanned records, estimated tokens, retrieval
latency, and prompt bytes.

## Offline Real-Data Copy

Generated workloads are useful for repeatability, but the next pre-production
step is to run the same measurement against copied or exported real data:

```sh
KOUTEN_REAL_JSONL=/path/to/corpus.jsonl \
QUERY_RING=docs/japan \
GLOBAL_BUDGET=40 \
ROUTED_BUDGET=10 \
examples/offline_effect_validation.sh
```

Expected JSONL shape:

```json
{"ring":"docs/japan","body":{"id":"doc-1","title":"...","text":"..."},"embedding":[1.0,0.0,0.0,0.0]}
```

This keeps the validation offline. It does not require production traffic and it
does not call an LLM unless the user separately chooses to run the generated
prompt through a model.

## Optional Trusted LLM Step

The effect validation does not require a model download. It always writes a
prompt first. A trusted local model can be added explicitly:

```sh
ollama pull gemma4:e2b
KOUTEN_TRUSTED_LLM_CMD='ollama run gemma4:e2b' examples/effect_validation_demo.sh
```

Gemma 4 E2B is used as the documented example because it is an official Google
Gemma 4 edge-size model available through Ollama.

References:

- https://deepmind.google/models/gemma/
- https://ai.google.dev/gemma/docs
- https://registry.ollama.com/library/gemma4

## JMeter Load Smoke

```sh
examples/jmeter_load_smoke.sh
KOUTEN_JMETER_THREADS=64 KOUTEN_JMETER_LOOPS=1000 examples/jmeter_load_smoke.sh
```

This is an optional Apache JMeter load smoke for the `koutend` TCP listener. It
sends concurrent `HEALTH` requests and writes a JTL result file.

It is deliberately separate from retrieval-locality benchmarks:

- JMeter health load checks listener stability and request/response behavior;
- effect-validation scripts check retrieval working-set and token reduction.

When JMeter is not installed, the wrapper exits successfully with a clear skip
message so the repository remains easy to test in minimal environments.

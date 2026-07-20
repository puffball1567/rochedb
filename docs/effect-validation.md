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

| case | docs | global budget | routed budget | set latency us | set us/record | scanned | tokens | retrieve latency us | scanned reduction | token reduction | prompt bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small-balanced | 168 | 8 | 3 | 2167.157 | 12.899744 | 168 -> 24 | 692 -> 260 | 953.418 -> 152.616 | 85.714% | 62.428% | 1356 |
| near-distractors | 1860 | 20 | 5 | 27266.134 | 14.659212 | 1860 -> 120 | 1730 -> 433 | 11846.404 -> 816.167 | 93.548% | 74.971% | 2064 |
| medium-noisy | 13500 | 30 | 8 | 186953.713 | 13.848423 | 13500 -> 500 | 2595 -> 692 | 81631.116 -> 3151.097 | 96.296% | 73.333% | 3124 |

Larger local validation with `KOUTEN_EFFECT_SCALE=100` and
`KOUTEN_EFFECT_BATCH_SIZE=10000`:

| case | docs | global budget | routed budget | set latency us | set us/record | scanned | tokens | retrieve latency us | scanned reduction | token reduction | prompt bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small-balanced | 16800 | 8 | 3 | 228004.308 | 13.571685 | 16800 -> 2400 | 692 -> 260 | 94720.037 -> 14593.993 | 85.714% | 62.428% | 1360 |
| near-distractors | 186000 | 20 | 5 | 2489114.827 | 13.382338 | 186000 -> 12000 | 1730 -> 433 | 1075884.485 -> 73365.860 | 93.548% | 74.971% | 2068 |
| medium-noisy | 1350000 | 30 | 8 | 16805714.971 | 12.448678 | 1350000 -> 50000 | 2595 -> 692 | 7410629.343 -> 289838.357 | 96.296% | 73.333% | 3128 |

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

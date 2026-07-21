# KoutenDB v0.8.1

KoutenDB v0.8.1 is a patch release that adds KoutenDB effect-validation demos
and chunked JSONL bulk-load imports.

Release:

https://github.com/puffball1567/koutendb/releases/tag/v0.8.1

## What Changed

- Added `examples/effect_validation_demo.sh`.
- Added `examples/effect_validation_demo.nim`.
- Added `examples/effect_validation_matrix.sh`.
- Added `examples/offline_effect_validation.sh`.
- Added optional Apache JMeter TCP health-load smoke assets:
  `examples/jmeter/koutendb-health-load.jmx` and
  `examples/jmeter_load_smoke.sh`.
- Added chunked JSONL bulk-load commits through `importJsonl(..., batchSize=N)`
  and `kouten import-jsonl --batch-size=N`.
- The demo generates a deterministic JSONL corpus, imports it into KoutenDB,
  compares global vs ring-routed retrieval, reports import latency,
  scanned-record reduction, estimated-token reduction, retrieval latency, and
  writes a compact prompt.
- The matrix script runs multiple generated workload shapes, including noisy
  and near-topic distractor cases, and prints Markdown result rows. The default
  matrix reaches 13,500,000 generated records; the large opt-in case reaches
  98,000,000. This is a manual validation path and is not part of the default
  CI smoke suite.
- The offline script lets users point the same measurement at copied/exported
  JSONL data before trying production traffic.
- LLM execution is optional through `KOUTEN_TRUSTED_LLM_CMD`, so the demo
  remains runnable without downloading a model.
- The recommended trusted small-model path is Gemma 4 E2B through Ollama:

```sh
ollama pull gemma4:e2b
KOUTEN_TRUSTED_LLM_CMD='ollama run gemma4:e2b' examples/effect_validation_demo.sh
```

Gemma 4 E2B is recommended because it is an official Google Gemma 4 edge-size
model available through Ollama. The demo intentionally does not recommend
arbitrary unknown model sources.

References:

- https://deepmind.google/models/gemma/
- https://ai.google.dev/gemma/docs
- https://registry.ollama.com/library/gemma4

Quick local sanity result from this release state:

| case | docs | set latency us | set us/record | scanned | tokens | retrieve latency us | scanned reduction | token reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small-balanced | 168 | 2167.157 | 12.899744 | 168 -> 24 | 692 -> 260 | 953.418 -> 152.616 | 85.714% | 62.428% |
| near-distractors | 1860 | 27266.134 | 14.659212 | 1860 -> 120 | 1730 -> 433 | 11846.404 -> 816.167 | 93.548% | 74.971% |
| medium-noisy | 13500 | 186953.713 | 13.848423 | 13500 -> 500 | 2595 -> 692 | 81631.116 -> 3151.097 | 96.296% | 73.333% |

Larger local validation with `KOUTEN_EFFECT_SCALE=100` and
`KOUTEN_EFFECT_BATCH_SIZE=10000`:

| case | docs | set latency us | set us/record | scanned | tokens | retrieve latency us | scanned reduction | token reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small-balanced | 16800 | 228004.308 | 13.571685 | 16800 -> 2400 | 692 -> 260 | 94720.037 -> 14593.993 | 85.714% | 62.428% |
| near-distractors | 186000 | 2489114.827 | 13.382338 | 186000 -> 12000 | 1730 -> 433 | 1075884.485 -> 73365.860 | 93.548% | 74.971% |
| medium-noisy | 1350000 | 16805714.971 | 12.448678 | 1350000 -> 50000 | 2595 -> 692 | 7410629.343 -> 289838.357 | 96.296% | 73.333% |

The default manual matrix can scale this same workload to 13,500,000 generated
records with `KOUTEN_EFFECT_SCALE=1000`. That larger run is intentionally not a
CI path; use it as a local stress validation with enough disk and memory
headroom.

## Why This Matters

KoutenDB's RAG story is not only about returning documents. It is about
measuring how much unrelated data can be avoided before downstream model work.
This demo makes that path concrete:

1. Generate a mixed corpus with useful and unrelated rings.
2. Import it through KoutenDB JSONL.
3. Compare global retrieval against ring-routed retrieval.
4. Report import latency, scanned-record reduction, estimated-token reduction,
   and retrieval latency.
5. Write a compact prompt from the routed context.
6. Repeat across a small matrix of workload shapes.
7. Run the same measurement against an offline real-data JSONL copy.
8. Optionally send that prompt to a trusted tiny local LLM.

The optional JMeter plan is intentionally scoped as a TCP health-load smoke. It
checks the server listener and request/response path under concurrent clients;
it is not presented as a retrieval benchmark.

## Verification

The patch was verified with:

- `nim check examples/effect_validation_demo.nim`
- `examples/effect_validation_demo.sh`
- `KOUTEN_EFFECT_QUICK=1 examples/effect_validation_matrix.sh`
- `examples/offline_effect_validation.sh` without `KOUTEN_REAL_JSONL`,
  confirming documented usage/error behavior
- `examples/jmeter_load_smoke.sh` with JMeter absent, confirming documented
  skip behavior
- `scripts/demo_smoke.sh`
- `scripts/test_all_smoke.sh`
- `nimble check`

The smoke path does not require Ollama or a model download; it verifies prompt
generation and the documented trusted-model command path.

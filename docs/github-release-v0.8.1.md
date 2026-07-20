# KoutenDB v0.8.1

KoutenDB v0.8.1 is a patch release that adds a tiny LLM RAG demo.

Release:

https://github.com/puffball1567/koutendb/releases/tag/v0.8.1

## What Changed

- Added `examples/tiny_llm_rag_demo.sh`.
- Added `examples/tiny_llm_rag_demo.nim`.
- The demo generates a deterministic JSONL corpus, imports it into KoutenDB,
  compares global vs ring-routed retrieval, and writes a compact prompt for a
  small local LLM.
- LLM execution is optional through `KOUTEN_TINY_LLM_CMD`, so the demo remains
  runnable without downloading a model.
- The recommended trusted small-model path is Gemma 4 E2B through Ollama:

```sh
ollama pull gemma4:e2b
KOUTEN_TINY_LLM_CMD='ollama run gemma4:e2b' examples/tiny_llm_rag_demo.sh
```

Gemma 4 E2B is recommended because it is an official Google Gemma 4 edge-size
model available through Ollama. The demo intentionally does not recommend
arbitrary unknown model sources.

References:

- https://deepmind.google/models/gemma/
- https://ai.google.dev/gemma/docs
- https://registry.ollama.com/library/gemma4

## Why This Matters

KoutenDB's RAG story is not only about returning documents. It is about reducing
the amount of unrelated context passed downstream. This demo makes that path
concrete:

1. Generate a mixed corpus with useful and unrelated rings.
2. Import it through KoutenDB JSONL.
3. Compare global retrieval against ring-routed retrieval.
4. Write a compact prompt from the routed context.
5. Optionally send that prompt to a trusted tiny local LLM.

## Verification

The patch was verified with:

- `nim check examples/tiny_llm_rag_demo.nim`
- `examples/tiny_llm_rag_demo.sh`
- `scripts/demo_smoke.sh`
- `scripts/test_all_smoke.sh`
- `nimble check`

The smoke path does not require Ollama or a model download; it verifies prompt
generation and the documented trusted-model command path.

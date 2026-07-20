## Tiny LLM RAG demo.
##
## Imports a small generated JSONL corpus, compares global vs ring-routed
## retrieval, and writes a compact prompt that can be passed to a trusted small
## local model such as Gemma 4 E2B via Ollama.

import std/[json, parseopt, strformat, strutils]
import ../src/koutendb

type
  DemoDoc = object
    id: string
    title: string
    text: string

proc vec(values: openArray[float32]): seq[float32] =
  for value in values:
    result.add value

proc parseDoc(payload: string): DemoDoc =
  let node = parseJson(payload)
  result.id = node{"id"}.getStr()
  result.title = node{"title"}.getStr()
  result.text = node{"text"}.getStr()

proc buildPrompt(question: string; ring: string; hits: seq[KoutenHit];
                 stats: RetrieveStats): string =
  result.add "You are answering from a small retrieved context.\n"
  result.add "Use only the context below. If the context is insufficient, say so.\n\n"
  result.add &"Question: {question}\n"
  result.add &"KoutenDB ring: {ring}\n"
  result.add &"Retrieved records: {hits.len}\n"
  result.add &"Scanned vectors: {stats.scanned}/{stats.totalVectors}\n"
  result.add &"Estimated context tokens: {stats.estimatedTokens}\n\n"
  result.add "Context:\n"
  for i, hit in hits:
    let doc = parseDoc(hit.payload)
    result.add &"[{i + 1}] id={doc.id} score={hit.score:.4f}\n"
    result.add &"title: {doc.title}\n"
    result.add &"text: {doc.text}\n\n"
  result.add "Answer:\n"

proc main() =
  var corpus = ""
  var dataDir = ""
  var promptOut = ""
  var ring = "docs/japan"
  var question = "How should a Japanese customer request a refund?"
  var globalBudget = 8
  var routedBudget = 3

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "corpus": corpus = val
      of "data": dataDir = val
      of "prompt-out": promptOut = val
      of "ring": ring = val
      of "question": question = val
      of "global-budget": globalBudget = parseInt(val)
      of "routed-budget": routedBudget = parseInt(val)
      else: discard
    of cmdArgument, cmdShortOption, cmdEnd:
      discard

  if corpus.len == 0 or dataDir.len == 0 or promptOut.len == 0:
    raise newException(ValueError,
      "usage: tiny_llm_rag_demo --corpus=FILE --data=DIR --prompt-out=FILE [--ring=RING] [--question=TEXT]")

  var db = open(dataDir = dataDir)
  defer: db.close()

  db.setGalaxyDescription("Tiny LLM RAG demo corpus")
  db.setRingDescription("docs/japan", "Japanese product and refund support notes")
  db.setRingDescription("docs/us", "US enterprise onboarding and billing notes")
  db.setRingDescription("support/errors", "Operational incident and error notes")
  db.setRingDescription("noise/general", "Unrelated background notes")

  let stats = db.importJsonl(corpus, defaultRing = "noise/general",
                             ringField = "ring",
                             payloadField = "body",
                             vecField = "embedding")

  let queryVec =
    if ring == "docs/japan":
      vec([1.0'f32, 0.02, 0.01, 0.0])
    elif ring == "docs/us":
      vec([0.01'f32, 1.0, 0.02, 0.0])
    elif ring == "support/errors":
      vec([0.0'f32, 0.02, 1.0, 0.02])
    else:
      vec([0.05'f32, 0.04, 0.03, 1.0])

  let global = db.retrieveWithStats(queryVec, budget = globalBudget)
  let routed = db.retrieveWithStats(queryVec, ring = ring, budget = routedBudget)
  let prompt = buildPrompt(question, ring, routed.hits, routed.stats)
  writeFile(promptOut, prompt)

  echo "== KoutenDB tiny LLM RAG demo =="
  echo &"corpus={corpus}"
  echo &"import read={stats.read} imported={stats.imported} skipped={stats.skipped} errors={stats.errors} rings={stats.rings}"
  echo &"question={question}"
  echo &"ring={ring}"
  echo &"global scanned={global.stats.scanned}/{global.stats.totalVectors} tokens~={global.stats.estimatedTokens} hits={global.hits.len}"
  echo &"routed scanned={routed.stats.scanned}/{routed.stats.totalVectors} tokens~={routed.stats.estimatedTokens} hits={routed.hits.len}"
  if global.stats.scanned > 0:
    echo &"scanned reduction vs global={100.0 * (1.0 - float(routed.stats.scanned) / float(global.stats.scanned)):.1f}%"
  if global.stats.estimatedTokens > 0:
    echo &"token reduction vs global={100.0 * (1.0 - float(routed.stats.estimatedTokens) / float(global.stats.estimatedTokens)):.1f}%"
  echo &"prompt={promptOut}"

when isMainModule:
  main()

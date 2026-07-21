## KoutenDB effect validation demo.
##
## Imports a small generated JSONL corpus, compares global vs ring-routed
## retrieval, and writes a compact prompt. The point is to measure KoutenDB's
## effect before an LLM is involved: scanned records, estimated context tokens,
## and prompt size.

import std/[json, monotimes, parseopt, strformat, strutils, times]
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
  var batchSize = 1000
  var diskBacked = false
  var metrics = false

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
      of "batch-size": batchSize = parseInt(val)
      of "disk-backed": diskBacked = true
      of "metrics": metrics = true
      else: discard
    of cmdArgument, cmdShortOption, cmdEnd:
      discard

  if corpus.len == 0 or dataDir.len == 0 or promptOut.len == 0:
    raise newException(ValueError,
      "usage: effect_validation_demo --corpus=FILE --data=DIR --prompt-out=FILE [--ring=RING] [--question=TEXT]")

  var db = open(dataDir = dataDir, diskBacked = diskBacked)
  defer: db.close()

  db.setGalaxyDescription("KoutenDB effect validation corpus")
  db.setRingDescription("docs/japan", "Japanese product and refund support notes")
  db.setRingDescription("docs/us", "US enterprise onboarding and billing notes")
  db.setRingDescription("support/errors", "Operational incident and error notes")
  db.setRingDescription("noise/general", "Unrelated background notes")

  var t = getMonoTime()
  let stats = db.importJsonl(corpus, defaultRing = "noise/general",
                             ringField = "ring",
                             payloadField = "body",
                             vecField = "embedding",
                             batchSize = batchSize)
  let setUs = float((getMonoTime() - t).inNanoseconds) / 1e3
  let setUsPerRecord =
    if stats.imported > 0:
      setUs / float(stats.imported)
    else:
      0.0
  var packUs = 0.0
  if diskBacked:
    t = getMonoTime()
    db.packDiskBackedSegments()
    packUs = float((getMonoTime() - t).inNanoseconds) / 1e3

  let queryVec =
    if ring == "docs/japan":
      vec([1.0'f32, 0.02, 0.01, 0.0])
    elif ring == "docs/us":
      vec([0.01'f32, 1.0, 0.02, 0.0])
    elif ring == "support/errors":
      vec([0.0'f32, 0.02, 1.0, 0.02])
    else:
      vec([0.05'f32, 0.04, 0.03, 1.0])

  t = getMonoTime()
  let global = db.retrieveWithStats(queryVec, budget = globalBudget)
  let globalUs = float((getMonoTime() - t).inNanoseconds) / 1e3
  t = getMonoTime()
  let routed = db.retrieveWithStats(queryVec, ring = ring, budget = routedBudget)
  let routedUs = float((getMonoTime() - t).inNanoseconds) / 1e3
  let prompt = buildPrompt(question, ring, routed.hits, routed.stats)
  writeFile(promptOut, prompt)

  let scanReduction =
    if global.stats.scanned > 0:
      100.0 * (1.0 - float(routed.stats.scanned) / float(global.stats.scanned))
    else:
      0.0
  let tokenReduction =
    if global.stats.estimatedTokens > 0:
      100.0 * (1.0 - float(routed.stats.estimatedTokens) / float(global.stats.estimatedTokens))
    else:
      0.0

  if metrics:
    echo &"effectImported {stats.imported}"
    echo &"effectImportBatches {stats.batches}"
    echo &"effectImportBatchSize {stats.batchSize}"
    echo &"effectDiskBacked {int(diskBacked)}"
    echo &"effectRings {stats.rings}"
    echo &"effectRing {ring}"
    echo &"effectSetLatencyUs {setUs:.3f}"
    echo &"effectSetLatencyUsPerRecord {setUsPerRecord:.6f}"
    echo &"effectPackLatencyUs {packUs:.3f}"
    echo &"effectGlobalScanned {global.stats.scanned}"
    echo &"effectGlobalTotal {global.stats.totalVectors}"
    echo &"effectGlobalTokens {global.stats.estimatedTokens}"
    echo &"effectGlobalHits {global.hits.len}"
    echo &"effectGlobalLatencyUs {globalUs:.3f}"
    echo &"effectRoutedScanned {routed.stats.scanned}"
    echo &"effectRoutedTotal {routed.stats.totalVectors}"
    echo &"effectRoutedTokens {routed.stats.estimatedTokens}"
    echo &"effectRoutedHits {routed.hits.len}"
    echo &"effectRoutedLatencyUs {routedUs:.3f}"
    echo &"effectScannedReductionPct {scanReduction:.3f}"
    echo &"effectTokenReductionPct {tokenReduction:.3f}"
    echo &"effectPromptBytes {prompt.len}"
    return

  echo "== KoutenDB effect validation demo =="
  echo &"corpus={corpus}"
  echo &"import read={stats.read} imported={stats.imported} skipped={stats.skipped} errors={stats.errors} rings={stats.rings}"
  echo &"set latency_us={setUs:.3f} set_us_per_record={setUsPerRecord:.6f}"
  if diskBacked:
    echo &"pack latency_us={packUs:.3f}"
  echo &"question={question}"
  echo &"ring={ring}"
  echo &"global scanned={global.stats.scanned}/{global.stats.totalVectors} tokens~={global.stats.estimatedTokens} hits={global.hits.len} latency_us={globalUs:.3f}"
  echo &"routed scanned={routed.stats.scanned}/{routed.stats.totalVectors} tokens~={routed.stats.estimatedTokens} hits={routed.hits.len} latency_us={routedUs:.3f}"
  echo &"scanned reduction vs global={scanReduction:.1f}%"
  echo &"token reduction vs global={tokenReduction:.1f}%"
  echo &"prompt bytes={prompt.len}"
  echo &"prompt={promptOut}"

when isMainModule:
  main()

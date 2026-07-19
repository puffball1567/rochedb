## orbelias/faiss_backend — optional FAISS vector backend.
##
## This module talks to a small C ABI bridge (`liborbelias_faiss.so`). The main
## OrbeliasDB build does not link FAISS directly; selecting vbFaiss requires the
## bridge library to be available at runtime.

import std/[algorithm, dynlib, os, tables]
import ./[store, vector_backend]

const FaissDynlib = "liborbelias_faiss.so"

type
  FaissHandle = pointer
  FaissNewProc = proc(dim: cint): FaissHandle {.cdecl.}
  FaissFreeProc = proc(h: FaissHandle) {.cdecl.}
  FaissAddProc = proc(h: FaissHandle, vec: ptr cfloat): cint {.cdecl.}
  FaissSearchProc = proc(h: FaissHandle, query: ptr cfloat, k: cint,
                         labels: ptr int64, scores: ptr cfloat): cint {.cdecl.}

  FaissApi = object
    lib: LibHandle
    newIndex: FaissNewProc
    freeIndex: FaissFreeProc
    add: FaissAddProc
    search: FaissSearchProc

  FaissEntry = object
    parent: uint64
    seq: uint32
    tWrite: float
    vec: seq[float32]
    payload: string

  FaissRingIndex = object
    handle: FaissHandle
    entries: seq[FaissEntry]
    indexed: Table[(uint64, uint32), int]

  FaissVectorBackend* = ref object of VectorBackend
    dim: int
    api: FaissApi
    global: FaissRingIndex
    rings: Table[uint64, FaissRingIndex]
    vectorCount: int

var cachedApi: FaissApi

proc candidateLibs(): seq[string] =
  let envPath = getEnv("ORBELIAS_FAISS_BRIDGE")
  if envPath.len > 0:
    result.add envPath
  result.add getCurrentDir() / "lib" / FaissDynlib
  result.add getAppDir() / ".." / "lib" / FaissDynlib
  result.add FaissDynlib

proc loadSym[T](lib: LibHandle, name: string): T =
  let p = lib.symAddr(name)
  if p == nil:
    raise newException(ValueError, "FAISS bridge missing symbol: " & name)
  cast[T](p)

proc loadFaissApi(): FaissApi =
  if cachedApi.lib != nil:
    return cachedApi
  var lib: LibHandle
  for path in candidateLibs():
    lib = loadLib(path)
    if lib != nil:
      break
  if lib == nil:
    raise newException(ValueError,
      "FAISS bridge not found. Build it with scripts/build_faiss_bridge.sh " &
      "or set ORBELIAS_FAISS_BRIDGE=/path/to/liborbelias_faiss.so")
  result.lib = lib
  result.newIndex = loadSym[FaissNewProc](lib, "orbelias_faiss_new")
  result.freeIndex = loadSym[FaissFreeProc](lib, "orbelias_faiss_free")
  result.add = loadSym[FaissAddProc](lib, "orbelias_faiss_add")
  result.search = loadSym[FaissSearchProc](lib, "orbelias_faiss_search")
  cachedApi = result

proc closeIndex(api: FaissApi, ix: var FaissRingIndex) =
  if ix.handle != nil:
    api.freeIndex(ix.handle)
  ix.handle = nil

proc ensureHandle(api: FaissApi, ix: var FaissRingIndex, dim: int) =
  if ix.handle == nil:
    ix.handle = api.newIndex(cint(dim))
    if ix.handle == nil:
      raise newException(ValueError, "FAISS bridge failed to create index")

proc addRaw(api: FaissApi, ix: var FaissRingIndex, dim: int, e: FaissEntry) =
  api.ensureHandle(ix, dim)
  if api.add(ix.handle, unsafeAddr e.vec[0]) == 0:
    raise newException(ValueError, "FAISS bridge failed to add vector")
  ix.indexed[(e.parent, e.seq)] = ix.entries.len
  ix.entries.add e

proc rebuild(api: FaissApi, ix: var FaissRingIndex, dim: int) =
  api.closeIndex(ix)
  ix.indexed.clear()
  if ix.entries.len == 0:
    return
  api.ensureHandle(ix, dim)
  for i, e in ix.entries:
    if api.add(ix.handle, unsafeAddr e.vec[0]) == 0:
      raise newException(ValueError, "FAISS bridge failed to rebuild index")
    ix.indexed[(e.parent, e.seq)] = i

proc newFaissVectorBackend*(): VectorBackend =
  FaissVectorBackend(kind: vbFaiss, api: loadFaissApi())

proc checkDim(b: FaissVectorBackend, vec: seq[float32]) =
  if vec.len == 0:
    return
  if b.dim != 0 and vec.len != b.dim:
    raise newException(ValueError, "FAISS vector dimension mismatch")

proc setDim(b: FaissVectorBackend, vec: seq[float32]) =
  if b.dim == 0:
    b.dim = vec.len
  b.checkDim(vec)

method upsert*(b: FaissVectorBackend, p: Particle) =
  if p.vec.len == 0:
    return
  b.setDim(p.vec)
  let k = (p.parent, p.seq)
  let e = FaissEntry(parent: p.parent, seq: p.seq, tWrite: p.tWrite,
                     vec: p.vec, payload: p.payload)
  if k in b.global.indexed:
    b.global.entries[b.global.indexed[k]] = e
    b.api.rebuild(b.global, b.dim)
    var ringIx = b.rings.getOrDefault(p.parent)
    if k in ringIx.indexed:
      ringIx.entries[ringIx.indexed[k]] = e
      b.api.rebuild(ringIx, b.dim)
      b.rings[p.parent] = ringIx
    return

  b.api.addRaw(b.global, b.dim, e)
  var ringIx = b.rings.getOrDefault(p.parent)
  b.api.addRaw(ringIx, b.dim, e)
  b.rings[p.parent] = ringIx
  inc b.vectorCount

proc removeFromIndex(api: FaissApi, ix: var FaissRingIndex, k: (uint64, uint32),
                     dim: int): bool =
  if k notin ix.indexed:
    return false
  let pos = ix.indexed[k]
  ix.indexed.del k
  ix.entries.delete(pos)
  api.rebuild(ix, dim)
  true

method remove*(b: FaissVectorBackend, parent: uint64, seq: uint32) =
  let k = (parent, seq)
  if b.api.removeFromIndex(b.global, k, b.dim):
    dec b.vectorCount
  if parent in b.rings:
    var ringIx = b.rings[parent]
    discard b.api.removeFromIndex(ringIx, k, b.dim)
    if ringIx.entries.len == 0:
      b.api.closeIndex(ringIx)
      b.rings.del parent
    else:
      b.rings[parent] = ringIx

method clear*(b: FaissVectorBackend) =
  b.api.closeIndex(b.global)
  b.global.entries.setLen(0)
  b.global.indexed.clear()
  for _, ix in b.rings.mpairs:
    b.api.closeIndex(ix)
  b.rings.clear()
  b.vectorCount = 0
  b.dim = 0

proc searchIndex(api: FaissApi, ix: var FaissRingIndex, totalVectors: int,
                 queryVec: seq[float32], budget: int): VectorSearchResult =
  if queryVec.len == 0 or budget <= 0 or ix.entries.len == 0:
    result.totalVectors = totalVectors
    result.skippedVectors = totalVectors
    return
  let k = min(budget, ix.entries.len)
  var labels = newSeq[int64](k)
  var scores = newSeq[float32](k)
  if api.search(ix.handle, unsafeAddr queryVec[0], cint(k),
                addr labels[0], addr scores[0]) == 0:
    raise newException(ValueError, "FAISS bridge search failed")
  result.totalVectors = totalVectors
  result.scanned = ix.entries.len
  result.skippedVectors = max(0, totalVectors - result.scanned)
  result.ringsTouched = 1
  for i in 0 ..< k:
    let pos = int(labels[i])
    if pos < 0 or pos >= ix.entries.len:
      continue
    let e = ix.entries[pos]
    result.hits.add VectorCandidate(parent: e.parent, seq: e.seq,
                                    tWrite: e.tWrite, score: float(scores[i]),
                                    payload: e.payload)
  result.hits.sort(proc(a, b: VectorCandidate): int = cmp(b.score, a.score))
  for h in result.hits:
    result.payloadBytes += h.payload.len
  result.estimatedTokens = (result.payloadBytes + 3) div 4

method search*(b: FaissVectorBackend, st: Store, queryVec: seq[float32],
               hasRing: bool, ringKey: uint64, budget: int): VectorSearchResult =
  b.checkDim(queryVec)
  if hasRing:
    if ringKey notin b.rings:
      result.totalVectors = b.vectorCount
      result.skippedVectors = b.vectorCount
      return
    var ix = b.rings[ringKey]
    result = b.api.searchIndex(ix, b.vectorCount, queryVec, budget)
    b.rings[ringKey] = ix
    return
  result = b.api.searchIndex(b.global, b.vectorCount, queryVec, budget)
  if b.rings.len == 0:
    result.ringsTouched = 0
  else:
    result.ringsTouched = min(b.rings.len, result.hits.len)

method searchMany*(b: FaissVectorBackend, st: Store, queryVec: seq[float32],
                   ringKeys: seq[uint64], budget: int): VectorSearchResult =
  b.checkDim(queryVec)
  if ringKeys.len == 0:
    return b.search(st, queryVec, false, 0'u64, budget)
  var seen = initTable[uint64, bool]()
  result.totalVectors = b.vectorCount
  for ring in ringKeys:
    if ring in seen or ring notin b.rings:
      continue
    seen[ring] = true
    var ix = b.rings[ring]
    let part = b.api.searchIndex(ix, b.vectorCount, queryVec, budget)
    b.rings[ring] = ix
    result.scanned += part.scanned
    result.payloadBytes += part.payloadBytes
    for h in part.hits:
      result.hits.add h
  result.ringsTouched = seen.len
  result.skippedVectors = max(0, b.vectorCount - result.scanned)
  result.hits.sort(proc(a, b: VectorCandidate): int = cmp(b.score, a.score))
  if result.hits.len > budget:
    result.hits.setLen(budget)
    result.payloadBytes = 0
    for h in result.hits:
      result.payloadBytes += h.payload.len
  result.estimatedTokens = (result.payloadBytes + 3) div 4

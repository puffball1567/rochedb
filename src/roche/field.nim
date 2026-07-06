## roche/field — ハロー凝集捕獲の slow 層（設計書 halo-capture §4）
##
## このモジュールは fast path に入らない。slow tick から予算付きで呼び出し、
## ハロー粒子の micro-clustering を維持する。

import std/[math, tables]
import ./store

const
  HaloKey* = 0'u64
  HaloPeriod* = 3600.0

type
  ClumpId* = uint32

  Clump* = object
    id*: ClumpId
    centroid*: seq[float32]
    members*: seq[(uint64, uint32)]
    massG*: float
    coherence*: float
    hystCount*: int
    updatedTick*: uint64

  FieldState* = ref object
    clumps*: seq[Clump]
    assigned*: Table[(uint64, uint32), ClumpId]
    forwarders*: Table[(uint64, uint32), Forwarder]
    ringCentroid*: Table[uint64, tuple[c: seq[float32], n: int]]
    tick*: uint64
    nextClumpId: ClumpId

proc newFieldState*(): FieldState =
  FieldState()

proc normalize*(v: seq[float32]): seq[float32] =
  var norm = 0.0
  for x in v:
    norm += float(x) * float(x)
  norm = sqrt(norm)
  result = newSeq[float32](v.len)
  if norm == 0.0:
    return
  for i, x in v:
    result[i] = float32(float(x) / norm)

proc cosineDistance*(a, b: seq[float32]): float =
  if a.len == 0 or a.len != b.len:
    return Inf
  var dot = 0.0
  for i in 0 ..< a.len:
    dot += float(a[i]) * float(b[i])
  1.0 - dot

proc blendCentroid(old, v: seq[float32], alpha: float): seq[float32] =
  result = newSeq[float32](old.len)
  for i in 0 ..< old.len:
    result[i] = float32(float(old[i]) * (1.0 - alpha) + float(v[i]) * alpha)
  result = result.normalize()

proc observeRingPut*(fs: FieldState, ring: uint64, vec: seq[float32]) =
  ## 環重心のインクリメンタル平均。vec は正規化済みを想定する。
  if vec.len == 0:
    return
  var e = fs.ringCentroid.getOrDefault(ring, (c: newSeq[float32](vec.len), n: 0))
  if e.c.len != vec.len:
    return
  for i in 0 ..< vec.len:
    e.c[i] = float32((float(e.c[i]) * float(e.n) + float(vec[i])) / float(e.n + 1))
  inc e.n
  e.c = e.c.normalize()
  fs.ringCentroid[ring] = e

proc liveMembers(st: Store, members: seq[(uint64, uint32)]): seq[(uint64, uint32)] =
  for id in members:
    if id in st.items:
      result.add id

proc recomputeStats(fs: FieldState, st: Store, rJoin: float) =
  for i in countdown(fs.clumps.high, 0):
    fs.clumps[i].members = st.liveMembers(fs.clumps[i].members)
    if fs.clumps[i].members.len == 0:
      fs.clumps.delete(i)
      continue

    let sampleN = min(fs.clumps[i].members.len, 64)
    var meanDist = 0.0
    for j in 0 ..< sampleN:
      let id = fs.clumps[i].members[j]
      meanDist += cosineDistance(st.items[id].vec, fs.clumps[i].centroid)
    meanDist /= float(sampleN)
    fs.clumps[i].coherence = max(0.0, min(1.0, 1.0 - meanDist / rJoin))
    fs.clumps[i].massG = float(fs.clumps[i].members.len) * fs.clumps[i].coherence

proc clusterTick*(fs: FieldState, st: Store, budget = 512, cMax = 256,
                  rJoin = 0.35) =
  ## ハロー粒子を最大 budget 件だけ見て clump に割り当てる。
  ## 一度割り当てた粒子の貼り直しはしない。
  inc fs.tick
  var seen = 0
  for id, p in st.items:
    if seen >= budget:
      break
    if p.parent != HaloKey or p.vec.len == 0 or id in fs.assigned:
      continue
    inc seen

    var bestIdx = -1
    var bestDist = Inf
    for i, c in fs.clumps:
      let d = cosineDistance(p.vec, c.centroid)
      if d < bestDist:
        bestDist = d
        bestIdx = i

    if bestIdx >= 0 and bestDist < rJoin:
      fs.clumps[bestIdx].members.add id
      let n = min(fs.clumps[bestIdx].members.len, 32)
      fs.clumps[bestIdx].centroid =
        blendCentroid(fs.clumps[bestIdx].centroid, p.vec, 1.0 / float(n))
      fs.clumps[bestIdx].updatedTick = fs.tick
      fs.assigned[id] = fs.clumps[bestIdx].id
    elif fs.clumps.len < cMax:
      let cid = fs.nextClumpId
      inc fs.nextClumpId
      fs.clumps.add Clump(id: cid, centroid: p.vec.normalize(),
                          members: @[id], coherence: 1.0, massG: 1.0,
                          updatedTick: fs.tick)
      fs.assigned[id] = cid

  fs.recomputeStats(st, rJoin)

proc bestCaptureTarget(fs: FieldState, c: Clump, nMin: int): tuple[found: bool, ring: uint64, dist: float] =
  result.dist = Inf
  for ring, rc in fs.ringCentroid:
    if ring == HaloKey or rc.n < nMin:
      continue
    let d = cosineDistance(c.centroid, rc.c)
    if d < result.dist:
      result = (true, ring, d)

proc adoptClump(fs: FieldState, st: Store, idx: int, target: uint64,
                now, forwardTtl: float) =
  let meta = st.ringMeta[target]
  let tx = st.beginTxn()
  for oldId in st.liveMembers(fs.clumps[idx].members):
    let p = st.items[oldId]
    let newSeq = st.nextSeq(target)
    tx.upsert Particle(parent: target, seq: newSeq, period: meta.period,
                       head: meta.head, tWrite: now, payload: p.payload,
                       vec: p.vec)
    let f = Forwarder(newParent: target, newSeq: newSeq,
                      newTWrite: now, expiresAt: now + forwardTtl)
    tx.remove(oldId[0], oldId[1])
    tx.putForwarder(oldId[0], oldId[1], f)
    fs.forwarders[oldId] = f
    fs.assigned.del oldId
  tx.commit()
  fs.clumps.delete(idx)

proc captureTick*(fs: FieldState, st: Store, now: float,
                  nMin = 16, r0 = 0.25, mCapture = 8.0,
                  cMin = 0.5, hTicks = 3, forwardTtl = 86400.0): int =
  ## 捕獲条件を満たした clump を 1 tick あたり 1 個だけ対象環へ移す。
  ## 移動とフォワーダ登録は Store transaction で atomic に行う。
  for i in 0 .. fs.clumps.high:
    let target = fs.bestCaptureTarget(fs.clumps[i], nMin)
    let ok = target.found and target.dist < r0 and
             fs.clumps[i].massG >= mCapture and
             fs.clumps[i].coherence >= cMin and
             target.ring in st.ringMeta
    if ok:
      inc fs.clumps[i].hystCount
    else:
      fs.clumps[i].hystCount = 0

    if fs.clumps[i].hystCount >= hTicks:
      fs.adoptClump(st, i, target.ring, now, forwardTtl)
      return 1
  0

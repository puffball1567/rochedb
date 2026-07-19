## orbeliassim — PoC Step 1–3 の検証 CLI（設計書 §12）
##
## usage: orbeliassim [bench|heatmap [e]|rendezvous|all]
##   bench      Step 1: ephemeris 評価コスト（完了条件 < 100 ns/call）
##   heatmap    Step 2: 時間的ロードバランシングのヒートマップと Gini 係数
##   rendezvous Step 3: 1:2 共鳴の会合予測とローカル JOIN 窓の検証

import std/[os, strutils, strformat, math, monotimes, times]
import orbelias/core

# 決定論的 LCG（外部依存なし・実行ごとに再現可能）
var rngState: uint64 = 0x9E3779B97F4A7C15'u64
proc nextRand(): float =
  rngState = rngState * 6364136223846793005'u64 + 1442695040888963407'u64
  float(rngState shr 11) / float(1'u64 shl 53)

proc gini(xs: seq[float]): float =
  var total = 0.0
  for x in xs: total += x
  if total == 0.0: return 0.0
  var s = 0.0
  for a in xs:
    for b in xs:
      s += abs(a - b)
  s / (2.0 * float(xs.len) * total)

proc runBench() =
  echo "== Step 1: ephemeris 評価コスト（完了条件: < 100 ns/call）=="
  let tbl = ArcTable(epoch: 1, nNodes: 8)
  let o = Orbit(a: 1.0, phi: 1.234, period: 60.0, e: 0.2, pomega: 0.7)
  const iters = 10_000_000
  var acc: uint64 = 0
  let start = getMonoTime()
  for i in 0 ..< iters:
    acc += uint64(tbl.node(o, float(i) * 0.001))
  let ns = (getMonoTime() - start).inNanoseconds
  let per = float(ns) / float(iters)
  echo &"  {iters} 回評価: {per:.1f} ns/call（検算値 acc={acc}）"
  echo if per < 100.0: "  → PASS" else: "  → FAIL"
  echo ""

proc runHeatmap(e: float) =
  echo &"== Step 2: 時間的ロードバランシング e={e}（1000 obj / 8 nodes / 2周）=="
  const
    nNodes = 8
    nObjs = 1000
    T = 60.0
    ticksPerPeriod = 240
    periods = 2
    cols = 48
    totalTicks = ticksPerPeriod * periods
  let pomega = PI / 8.0   # 遠点（ϖ+π = 9π/8）が node4 の弧中央に来るよう選ぶ
  let tbl = ArcTable(epoch: 1, nNodes: uint16(nNodes))
  var orbits: seq[Orbit]
  for i in 0 ..< nObjs:
    orbits.add Orbit(a: 1.0, phi: nextRand() * TAU, period: T, e: e, pomega: pomega)
  let dt = T / float(ticksPerPeriod)
  var grid: array[nNodes, array[cols, float]]
  var totals = newSeq[float](nNodes)
  for tick in 0 ..< totalTicks:
    let t = float(tick) * dt
    let col = tick * cols div totalTicks
    for o in orbits:
      let nd = int(tbl.node(o, t))
      grid[nd][col] += 1.0
      totals[nd] += 1.0
  var maxCell = 0.0
  for nd in 0 ..< nNodes:
    for c in 0 ..< cols:
      maxCell = max(maxCell, grid[nd][c])
  const shades = " .:-=+*#%@"
  for nd in 0 ..< nNodes:
    var row = ""
    for c in 0 ..< cols:
      row.add shades[min(9, int(grid[nd][c] / maxCell * 9.999))]
    let mark = if e > 0.0 and nd == nNodes div 2: "  ← 遠点（滞在最長）" else: ""
    echo &"  node{nd} |{row}|{mark}"
  echo &"  時間 →（0..{float(periods) * T:.0f}s、1列={float(periods) * T / float(cols):.1f}s）"
  # 実測シェア vs 式（滞在比 = ΔM/2π を meanAtTheta で逆算、§1）
  let refOrb = Orbit(a: 1.0, phi: 0.0, period: T, e: e, pomega: pomega)
  var grand = 0.0
  for x in totals: grand += x
  echo "  node    実測シェア   式からの予測"
  for nd in 0 ..< nNodes:
    let s = tbl.arcStart(NodeId(nd))
    var d = refOrb.meanAtTheta(wrap(s + tbl.arcWidth)) - refOrb.meanAtTheta(s)
    if d < 0.0: d += TAU
    echo &"  node{nd}   {totals[nd] / grand * 100:6.2f}%      {d / TAU * 100:6.2f}%"
  let g = gini(totals)
  let verdict =
    if e == 0.0: (if g < 0.1: "  → PASS（< 0.1）" else: "  → FAIL")
    else: "  （e>0: 意図した偏り。式と一致していれば OK）"
  echo &"  Gini = {g:.4f}" & verdict
  echo ""

proc runRendezvous() =
  echo "== Step 3: 1:2 共鳴 JOIN（完了条件: 会合時刻で同一ノード 100%）=="
  let tbl = ArcTable(epoch: 1, nNodes: 8)
  let o1 = circular(0.3, 30.0)   # 速い軌道
  let o2 = circular(5.5, 60.0)   # 遅い軌道（1:2 共鳴）
  echo &"  T1=30s, T2=60s → 会合周期 T_syn = {synodicPeriod(30.0, 60.0):.0f}s"
  let predictedWin = conjunctionWindow(tbl, o1, o2)
  let ts = conjunctions(o1, o2, 0.0, 240.0)
  const dt = 0.001
  var allPass = true
  for tk in ts:
    let n1 = tbl.node(o1, tk)
    let n2 = tbl.node(o2, tk)
    var lo = tk
    while tbl.node(o1, lo - dt) == tbl.node(o2, lo - dt): lo -= dt
    var hi = tk
    while tbl.node(o1, hi + dt) == tbl.node(o2, hi + dt): hi += dt
    let ok = n1 == n2
    allPass = allPass and ok
    let okStr = if ok: "一致" else: "不一致!"
    echo &"  t={tk:7.2f}s  node{n1}/node{n2} {okStr}  実測窓={hi - lo:.2f}s（予測 {predictedWin:.2f}s）"
  echo if allPass: "  → PASS: 全会合で同一ノード＝ローカル JOIN 成立"
       else: "  → FAIL"
  echo &"  プランナ例: t=0 の JOIN 要求 →「次会合まで {ts[0]:.1f}s 待つ」vs「今すぐ転送」を閉じた式で比較できる（§8）"
  echo ""

when isMainModule:
  let cmd = if paramCount() >= 1: paramStr(1) else: "all"
  case cmd
  of "bench":
    runBench()
  of "heatmap":
    if paramCount() >= 2: runHeatmap(parseFloat(paramStr(2)))
    else:
      for e in [0.0, 0.1, 0.3]: runHeatmap(e)
  of "rendezvous":
    runRendezvous()
  of "all":
    runBench()
    for e in [0.0, 0.1, 0.3]: runHeatmap(e)
    runRendezvous()
  else:
    echo "usage: orbeliassim [bench|heatmap [e]|rendezvous|all]"
    quit(1)

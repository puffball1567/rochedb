## roche/core — ephemeris 評価の fast 層（設計書 §1–§2, §8）
##
## 規律: `theta`/`owner`/`node` が fast 層のすべて。sin 1回＋弧表引きで所在が出る。
## 質量（m_i / m_g）はこのモジュールに一切登場しない（設計書 §5:
## 質量は elements を書き換える slow 層の力であって、位置計算には効かせない）。

import std/[math, algorithm]

export math.TAU   # 角度定数は math のものを使う（独自定義は識別子衝突のもと）

const
  EMax* = 0.3
    ## 離心率の上限（設計書 §1 歯止め）。一次近似 θ = M + 2e·sin(M−ϖ) の
    ## 誤差 O(e²) と dθ/dM = 1 + 2e·cos > 0（単調・可逆）を保つ範囲に制限する。

type
  NodeId* = uint16

  Orbit* = object
    ## 軌道要素（設計書 §1）。
    a*: float        ## 帯。Heavy: 円盤半径=重要度シェル / Particle: 環の温度半径（§4）
    phi*: float      ## t=0 での平均経度 [rad]
    period*: float   ## 公転周期 T [s]。Heavy は事実上 Inf（固定, §6.2）
    e*: float        ## 滞在偏り（0=均等, ≤ EMax）
    pomega*: float   ## 近点角 ϖ。滞在が最長になる遠点は ϖ + π

  ArcTable* = object
    ## epoch ごとのリング弧所有表（§9）。PoC は等分割弧。
    epoch*: uint32
    nNodes*: uint16

  OrbitalId* = object
    ## 自己記述ID（§2.2）: elements は id から計算する。粒子ごとの所在表は存在しない。
    parent*: uint64
    epoch*: uint32
    tWrite*: float
    seq*: uint32

proc wrap*(x: float): float {.inline.} =
  ## [0, 2π) へ正規化
  result = x mod TAU
  if result < 0.0: result += TAU

proc angDist*(x, y: float): float =
  ## 円周上の距離（テスト・検証用）
  let d = wrap(x - y)
  min(d, TAU - d)

proc circular*(phi, period: float): Orbit =
  Orbit(a: 1.0, phi: phi, period: period, e: 0.0, pomega: 0.0)

# ---------------------------------------------------------------- fast 層

proc meanLongitude*(o: Orbit, t: float): float {.inline.} =
  ## M(t) = φ + 2π·t/T
  wrap(o.phi + TAU * t / o.period)

proc theta*(o: Orbit, t: float): float {.inline.} =
  ## θ(t) = M + 2e·sin(M − ϖ) — 中心差の一次近似（設計書 §1）。sin 1回で終わる。
  let m = o.meanLongitude(t)
  wrap(m + 2.0 * o.e * sin(m - o.pomega))

proc arcWidth*(tbl: ArcTable): float {.inline.} = TAU / float(tbl.nNodes)

proc arcStart*(tbl: ArcTable, n: NodeId): float = float(n) * tbl.arcWidth

proc owner*(tbl: ArcTable, th: float): NodeId {.inline.} =
  NodeId(int(wrap(th) / TAU * float(tbl.nNodes)) mod int(tbl.nNodes))

proc node*(tbl: ArcTable, o: Orbit, t: float): NodeId {.inline.} =
  ## node(id, t) = arc_owner(θ(t)) — 誰にも問い合わせない所在解決（概念書 2章）
  tbl.owner(o.theta(t))

# ---------------------------------------------------------------- slow パス（予測・逆算）

proc meanAtTheta*(o: Orbit, target: float): float =
  ## θ = target となる平均経度 M の逆算（境界予測・滞在比計算用の slow パス）。
  ## dθ/dM = 1 + 2e·cos ≥ 1 − 2·EMax > 0 なので単調で、Newton 反復が安全に収束する。
  var m = target
  for _ in 0 ..< 20:
    let f = m + 2.0 * o.e * sin(m - o.pomega) - target
    if abs(f) < 1e-12: break
    m -= f / (1.0 + 2.0 * o.e * cos(m - o.pomega))
  wrap(m)

proc nextArrival*(o: Orbit, target: float, t: float): float =
  ## t 以降で θ が target 角に到達する最初の時刻。
  ## ハンドオフの事前転送（§6.1）と弾道プリフェッチ（概念書 2.3③）の基礎。
  let mNow = o.meanLongitude(t)
  let mTarget = o.meanAtTheta(target)
  var dm = mTarget - mNow
  if dm < 0.0: dm += TAU
  t + dm / TAU * o.period

# ---------------------------------------------------------------- OrbitalId（§2.2）

proc ringOrbit*(id: OrbitalId, ringPeriod: float, headAngle: float = 0.0,
                aInner: float = 0.0): Orbit =
  ## 粒子は書き込み時刻のヘッド位置（環ごとの固定角 headAngle）に追記され、
  ## プラッタと共に公転する:
  ##   θ_p(t) = headAngle + 2π·(t − tWrite)/T
  ## ちょうど1回転後にヘッド下へ戻る＝ヘッドは粒子を時系列順に舐める
  ## （§4.2「1回転=1エポック」）。所在は id・親の周期・ヘッド角だけから出る
  ## （親情報は almanac にあるので、粒子ごとの所在表は不要 = §2.2）。
  Orbit(a: aInner, phi: wrap(headAngle - TAU * id.tWrite / ringPeriod),
        period: ringPeriod, e: 0.0, pomega: 0.0)

# ---------------------------------------------------------------- 会合（§8）

proc synodicPeriod*(t1, t2: float): float =
  ## T_syn = T₁T₂ / |T₁ − T₂|
  t1 * t2 / abs(t1 - t2)

proc conjunctions*(o1, o2: Orbit, fromT, horizon: float): seq[float] =
  ## e=0 の2軌道が同角度（⇒同弧⇒同ノード⇒ローカル JOIN 窓）になる時刻列。閉じた式。
  doAssert o1.e == 0.0 and o2.e == 0.0,
    "e>0 の会合予測は nextArrival の反復で行う（Step 4 以降）"
  let rate = TAU * (1.0 / o1.period - 1.0 / o2.period)
  doAssert rate != 0.0, "同周期は位相差で常時会合/非会合が決まる（会合『時刻列』はない）"
  # φ₁ + 2π·t/T₁ = φ₂ + 2π·t/T₂ + 2π·k を t について解く
  let dphi = o2.phi - o1.phi
  let tEnd = fromT + horizon
  let kA = (rate * fromT - dphi) / TAU
  let kB = (rate * tEnd - dphi) / TAU
  result = @[]
  for k in int(ceil(min(kA, kB))) .. int(floor(max(kA, kB))):
    result.add (dphi + TAU * float(k)) / rate
  result.sort()

proc conjunctionWindow*(tbl: ArcTable, o1, o2: Orbit): float =
  ## 会合を挟んで両者が同一弧に留まる連続時間。
  ## 導出: 会合点を含む弧を速い方が通過する時間に等しく、会合点の弧内位置に依らない
  ##   window = 弧幅 / max(ω₁, ω₂)
  tbl.arcWidth / max(TAU / o1.period, TAU / o2.period)

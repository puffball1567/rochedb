## kouten/planner_backend — retrieval plan ranking backend boundary.
##
## KoutenDB core keeps a deterministic heuristic planner. Model-based optimizers
## stay outside the read path; agents can use atlas/stats/explain output instead.

import std/algorithm

type
  PlannerBackendKind* = enum
    pbHeuristic

  RingPlanCandidate* = object
    key*: uint64
    name*: string
    score*: float
    centroidScore*: float
    ringCount*: int
    utility*: float
    isBase*: bool
    isSibling*: bool
    isDescendant*: bool

  PlannerSelection* = object
    selected*: seq[RingPlanCandidate]
    pruned*: seq[RingPlanCandidate]
    reason*: string

  PlannerBackend* = ref object
    kind*: PlannerBackendKind

proc newHeuristicPlannerBackend*(): PlannerBackend =
  PlannerBackend(kind: pbHeuristic)

proc boolRank(v: bool): int =
  if v: 1 else: 0

proc selectRings*(b: PlannerBackend, candidates: seq[RingPlanCandidate],
                  limit = 0): PlannerSelection =
  case b.kind
  of pbHeuristic:
    result.reason = "heuristic centroid ranking"
    var ordered = candidates
    ordered.sort(proc(a, b: RingPlanCandidate): int =
      let byBase = cmp(boolRank(b.isBase), boolRank(a.isBase))
      if byBase != 0:
        return byBase
      let byCentroid = cmp(b.centroidScore, a.centroidScore)
      if byCentroid != 0:
        return byCentroid
      let byUtility = cmp(b.utility, a.utility)
      if byUtility != 0:
        return byUtility
      let byCount = cmp(b.ringCount, a.ringCount)
      if byCount != 0:
        return byCount
      cmp(a.name, b.name)
    )
    for i, c in ordered:
      if limit > 0 and i >= limit:
        result.pruned.add c
      else:
        result.selected.add c

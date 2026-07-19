# Topology Remapping

OrbeliasDB's first owner mapping was intentionally simple: divide the angle space
equally by `nNodes`, then choose the owner from the current angle.

That is useful for a small static cluster, but it has an important weakness:
changing `nNodes` can move far more data than necessary. v0.6 adds the core
primitives needed to model safer topology changes without abandoning OrbeliasDB's
coordinate-based placement model.

## Arc Tables

`ArcTable` now supports two modes:

| Mode | Meaning |
| --- | --- |
| Equal arcs | The legacy-compatible mode. `arcs` is empty, and the angle space is divided evenly by `nNodes`. |
| Explicit arcs | The angle space is represented by sorted `(start, node)` entries. Each entry owns `[start, nextStart)`. |

Equal arcs keep simple deployments simple. Explicit arcs are the foundation for
weighted placement, virtual arcs, and future topology epochs.

## Weighted Arcs

Weighted arcs allocate one contiguous arc per node according to a weight list.

Example:

```nim
let tbl = weightedArcTable(epoch = 1, weights = [1, 3])
```

This gives node `0` roughly 25% of the angle space and node `1` roughly 75%.
It is useful when nodes have different capacity, but it is still a coarse
layout because each node receives one large contiguous region.

## Virtual Arcs

Virtual arcs create many small deterministic arcs per node.

Example:

```nim
let tbl = virtualArcTable(epoch = 1, nNodes = 8, virtualArcsPerNode = 64)
```

The important property is stability. Existing node/slot arc positions are
derived from deterministic hashes. Adding a node introduces that node's virtual
arcs without recomputing all existing node positions from `mod nNodes`.

This is closer to the operational goal:

- keep coordinate-based ownership;
- reduce unnecessary remapping during membership changes;
- allow future topology epochs to be planned and measured before activation.

## Remap Measurement

`remapFraction` estimates how much of the angle space changes owner between two
topologies.

Example:

```nim
let before = virtualArcTable(epoch = 1, nNodes = 8, virtualArcsPerNode = 64)
let after = virtualArcTable(epoch = 2, nNodes = 9, virtualArcsPerNode = 64)
let moved = remapFraction(before, after, samples = 8192)
```

This is a planning metric. It does not move records by itself. It gives tests,
operators, and future automation a concrete way to compare topology choices.

## Current Boundary

This feature is a remapping foundation, not a complete online rebalance system.

Implemented:

- explicit arc-table ownership;
- weighted arc-table construction;
- deterministic virtual arc-table construction;
- topology validation;
- remap-fraction measurement;
- unit tests proving virtual arcs reduce movement versus equal `nNodes`
  remapping for the covered scenario.

Still future work:

- persisted topology-epoch files;
- online membership change workflow;
- staged migration / compaction integration;
- operational CLI for previewing and applying topology changes.

The design goal is to avoid turning OrbeliasDB into a generic distributed hash
table. The topology layer should support OrbeliasDB's locality model: records
remain placed by meaningful coordinates, while cluster membership changes avoid
unnecessary movement.

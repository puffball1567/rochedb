---
layout: page
title: Public API
---

# Public API

This page summarizes the stable user-facing API surface for the current
technical preview. The canonical Nim definitions live in `src/rochedb.nim`.

## Core Types

| Type | Important fields | Meaning |
|---|---|---|
| `RocheDb` | opaque handle | Embedded or cluster database handle. |
| `RocheId` | opaque; printable as `parent:seq` | ID returned by `put`; pass it to `get`, `query`, `locate`, `nextVisit`, and `nextJoin`. |
| `RocheTx` | opaque transaction handle | Transaction context returned by `beginTransaction`. |
| `GalaxyRouter` | opaque router handle | Holds named galaxy connections for applications that access multiple galaxies. |
| `RocheRecord` | `id`, `payload` | Lightweight record returned by `listByRing`. |
| `RocheListPage` | `items`, `nextCursor` | Cursor-paginated list result. Empty `nextCursor` means there is no next page. |
| `RocheHit` | `id`, `score`, `payload` | Retrieval hit. `score` is cosine similarity, higher is closer. |

`RocheId` should normally be treated as opaque. `toRaw` and `fromRaw` exist for
C ABI / driver boundaries and CLI reproducibility, not as the preferred
application model.

## Retrieval Types

| Type | Important fields | Meaning |
|---|---|---|
| `RetrieveStats` | `totalVectors`, `scanned`, `skippedVectors`, `returned`, `ringsTouched`, `payloadBytes`, `estimatedTokens`, `candidateReduction` | Explains how much work retrieval avoided or performed. |
| `RetrievalPlan` | `strategy`, `baseRing`, `amount`, `scope`, `depth`, `budget`, `focus`, `effectiveTopRings`, `selectedRings`, `prunedRings`, `reason` | Human-readable execution plan for retrieval tuning. |
| `RingMetric` | `ringKey`, `count`, `coherence` | Low-level ring population and coherence metric. |
| `RocheRingSummary` | `ringKey`, `count`, `centroid`, `score`, `coherence`, `massG` | Ring summary used by atlas/planner-style workflows. |
| `RetrievalEnvelopeOptions` | `provider`, `galaxy`, `ring`, `requestId`, `sourceType`, `retentionClass`, `plan` | Metadata for RAG/MCP adapters. |

For application-facing tuning, prefer `SearchProfile` over raw numeric knobs:

| Type | Values | Meaning |
|---|---|---|
| `ResultAmount` | `raFew`, `raNormal`, `raMany`, `raAllUseful` | How much useful context to keep. |
| `SearchScope` | `ssTight`, `ssNear`, `ssWide`, `ssAll` | How broadly to search related rings. |
| `SearchDepth` | `sdShallow`, `sdNormal`, `sdDeep`, `sdVeryDeep` | How far to descend ring hierarchy. |
| `SearchProfile` | `amount`, `scope`, `depth`, `note` | Named human-facing retrieval profile. |
| `RetrievalTuning` | `budget`, `focus`, `topRings`, `branchBudget`, `maxDepth`, `includeChildren` | Lower-level retrieval knobs. Use when you need explicit tuning. |

## Sync And Job Types

| Type | Important fields | Meaning |
|---|---|---|
| `UniverseSyncEvent` | `id`, `eventKey`, `sourceUniverse`, `sourceGalaxy`, `ring`, `logicalKey`, `payload`, `timestamp`, `acknowledged`, `error` | Durable eventual-convergence event in the source outbox. |
| `UniverseSyncStats` | `read`, `applied`, `skipped`, `acked`, `pruned`, `errors` | One-shot sync result. |
| `RingApplyPolicy` | `mode`, `historyKeep`, `delayMs` | Per-ring universe apply behavior. |
| `RingApplyMode` | `ramLatestOnly`, `ramAppendOnly`, `ramBoundedHistory`, `ramDelayedTimestamp` | How a ring treats replay, history, and delayed timestamp apply. |
| `WarpJob` | `id`, `rings`, `whereField`, `equals`, `patch`, `status`, `attempts`, `retryAt`, `acknowledged`, `error` | Delayed ring-scoped JSON patch job. |
| `WarpStepResult` | `job`, `scanned`, `matched`, `updated` | Result from one `warpStep`. |
| `WarpStatus` | `wsPending`, `wsRunning`, `wsDone`, `wsFailed`, `wsDeadLetter` | Warp job lifecycle. |

## Persistence Types

| Type | Important fields | Meaning |
|---|---|---|
| `CompactStats` | store-defined | Result of WAL compaction. |
| `BackupStats` | store-defined | Result of backup / verify / restore operations. |
| `DumpStats` | `bytes`, `records`, `rings`, `documents`, `destination` | JSONL dump summary. |
| `ImportStats` | `read`, `imported`, `skipped`, `errors`, `rings`, `source`, `defaultRing` | JSONL import summary. |
| `RocheDurability` | `durBuffered`, `durStrong` | WAL durability mode. |

## Handles

| API | Purpose |
|---|---|
| `open(dataDir = "", nodes = 8, durability = durBuffered)` | Open embedded RocheDB. Omit `dataDir` for memory-only mode. |
| `connect(peers, username = "", password = "", authToken = "", secretKey = "", galaxy = "")` | Connect to a running `roched` cluster. |
| `close(db)` | Close embedded or cluster resources. |
| `openGalaxyRouter()` | Create a local router for multiple named galaxies. |
| `addGalaxy(router, name, peers, ...)` | Register a remote galaxy connection. |
| `galaxy(router, name)` | Get a `RocheDb` handle for one galaxy. |

## Documents

| API | Purpose |
|---|---|
| `put(payload, ring = "default", vec = @[])` | Store a string payload in a ring. |
| `put(doc: JsonNode, ring = "default", vec = @[])` | Store a JSON document. |
| `put(encodedPayload(bytes, codec), ring, vec)` | Store `raw`, `json`, `nif`, or `bif` bytes with format metadata. |
| `get(id)` | Fetch by RocheDB ID. |
| `getEncoded(id)` | Fetch payload bytes together with their `PayloadCodec`. |
| `query(id, selection)` | Fetch a JSON projection using GraphQL-style selection syntax. |
| `prepareSelection(selection)` / `query(id, prepared)` | Validate and compile a reusable projection before execution. |
| `exists(id)` / `contains(id)` | Check whether an ID exists. |
| `update(id, payload)` / `update(id, doc)` | Replace an existing document. |
| `patch(id, patchDoc)` | Apply a JSON merge patch. |
| `deleteById(id)` / `remove(id)` | Delete by ID. |
| `batchPut(payloads, ring, vecs)` | Insert multiple records. |
| `batchGet(ids)` | Fetch multiple IDs. |
| `batchDelete(ids)` | Delete multiple IDs. |

The C ABI exposes matching additive functions: `roche_put_codec`,
`roche_put_vec_codec`, and `roche_get_codec`. See [Payload Codecs](payload-codecs.md).

## Ring Reads

| API | Purpose |
|---|---|
| `listByRing(ring, limit = 100, cursor = "")` | List records in one ring with cursor pagination. |
| `countByRing(ring)` | Count records in one ring. |
| `retrieve(queryVec, ring = "", budget = 8, ...)` | Vector/RAG-style retrieval with ring-aware planning. |
| `retrievalPlan(...)` | Build a readable retrieval plan without executing it. |
| `tunedRetrievalPlan(db, profile = "default", ...)` | Build a plan from a stored profile. |
| `searchPlan(...)` | Build a plan from human-facing amount/scope/depth terms. |
| `ringMetrics()` | Return low-level ring metrics. |
| `ringSummaries(queryVec = @[])` | Return ring centroids, coherence, mass, and optional similarity scores. |
| `retrievalEnvelope(...)` | Return retrieval results with source metadata for RAG/MCP adapters. |

## Placement And Observability

| API | Purpose |
|---|---|
| `locate(id, at = -1.0)` | Compute the owning node for an ID at the current or specified time. |
| `nextVisit(id, node)` | Compute when an ID next visits a node. |
| `nextJoin(a, b)` | Compute the next co-location time for two RocheDB IDs. |
| `stats()` | Return per-node item counts. |

## Transactions

| API | Purpose |
|---|---|
| `beginTransaction()` | Start a transaction. |
| `tx.put(...)` | Stage a write. |
| `tx.update(...)` | Stage an update. |
| `tx.remove(id)` | Stage a delete. |
| `tx.commit()` | Commit. |
| `tx.rollback()` | Roll back. |
| `transaction(db, proc(tx))` | Helper that rolls back on exception. |

Cluster transactions are a PoC. They use a landing intent and retry apply, but
coordinator redundancy is still planned.

## Atlas And Descriptions

| API | Purpose |
|---|---|
| `setGalaxyDescription(description)` | Set a galaxy-level map description. |
| `getGalaxyDescription()` | Read the galaxy description. |
| `setRingDescription(ring, description)` | Set a ring map description. |
| `getRingDescription(ring)` | Read a ring description. |
| `atlas()` | Return a galaxy/ring map for agents and tools. |

## Persistence And Data Movement

| API | Purpose |
|---|---|
| `compact()` | Rebuild the WAL from live records. |
| `backup(dstDir)` | Create a compact backup. |
| `backupEncrypted(dstDir, passphrase)` | Create an encrypted backup. |
| `verifyBackup(backupDir)` | Verify a backup. |
| `restoreBackup(backupDir, dataDir, overwrite = false)` | Restore into a data directory. |
| `dump(path = "", includeVectors = true)` | Export JSONL. |
| `importJsonl(path, defaultRing = "imported", ...)` | Import JSONL with ring routing. |

## Universe Sync And Warp

| API | Purpose |
|---|---|
| `putSynced(...)` | Store locally and append a universe sync event. |
| `universeSyncEvents(includeAcknowledged = false)` | Inspect source outbox events. |
| `applyUniverseSyncEvent(event)` | Apply one sync event idempotently. |
| `ackUniverseSyncEvent(eventId)` | Mark a source event acknowledged. |
| `pruneAckedUniverseSyncEvents()` | Remove acknowledged source events. |
| `syncUniverseOnce(source, target, pruneAcked = false)` | One-shot local data-dir sync. |
| `enqueueWarp(...)` | Queue a delayed ring-scoped JSON patch. |
| `warpStep(jobId, maxRecords = 100)` | Advance one warp job. |
| `warpDrain(jobId)` | Run a warp job until done or bounded. |
| `ackWarp(jobId)` / `pruneAckedWarpJobs()` | Acknowledge and clean completed jobs. |

## Configuration APIs

| API | Purpose |
|---|---|
| `configureVectorBackend(kind)` | Select exact or FAISS vector backend. |
| `configurePlannerBackend(kind)` | Select deterministic planner backend. |
| `configureRetrievalTuning(profile, ...)` | Define numeric retrieval knobs. |
| `configureSearchProfile(name, amount, scope, depth)` | Define human-facing retrieval profile. |
| `configureRing(ring, period)` | Configure ring orbit period. |
| `configureWriteAckMode(mode)` | Set default write acknowledgement mode. |
| `configureRingWriteAckMode(ring, mode)` | Override write acknowledgement per ring. |
| `configureRingApplyPolicy(ring, policy)` | Configure universe apply behavior for one ring. |

See [Configuration Reference](config-reference.md) for property names and
recommended defaults.

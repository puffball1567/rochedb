import Foundation
import Testing
@testable import OrbeliasDB

@Test func embeddedRoundtripRetrieveAndAtlas() throws {
    let db = try OrbeliasDB.open(nodes: 8)
    defer { db.close() }

    try db.setGalaxyDescription("Swift test galaxy")
    try db.setRingDescription("docs/swift", description: "Swift driver documents")
    try db.configureRing("docs/swift", period: 30.0)

    let id = try db.putVec("docs/swift", payload: "hello swift", vector: [1.0, 0.0])
    #expect(try db.getString(id) == "hello swift")

    let batch = try db.batchGet([id])
    #expect(batch.count == 1)
    #expect(String(data: batch[0], encoding: .utf8) == "hello swift")

    let result = try db.retrieve(vector: [1.0, 0.0], ring: "docs/swift", budget: 4)
    #expect(result.hits.count == 1)
    #expect(result.stats.scanned == 1)

    let atlas = try db.atlas(queryVector: [1.0, 0.0], maxCentroidDims: 8)
    #expect(atlas.contains("Swift test galaxy"))
    #expect(atlas.contains("Swift driver documents"))

    let node = try db.locate(id)
    #expect(node >= 0)
    #expect(try db.nextVisit(id, node: Int32(node)) >= 0.0)
}

@Test func closePreventsFurtherUse() throws {
    let db = try OrbeliasDB.open(nodes: 8)
    db.close()

    do {
        _ = try db.put("docs", payload: "x")
        Issue.record("expected closed error")
    } catch OrbeliasDBError.closed {
    }
}

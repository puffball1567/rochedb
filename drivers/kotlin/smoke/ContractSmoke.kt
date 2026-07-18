import org.rochedb.RocheDb

private fun checkState(condition: Boolean, message: String) {
    if (!condition) error(message)
}

fun main() {
    checkState(RocheDb.abiVersion == 2, "unexpected ABI version")

    RocheDb.open(4).use { db ->
        db.configureRing("docs", 45.0)
        db.setGalaxyDescription("Smoke-test galaxy for Kotlin binding.")
        db.setRingDescription("docs", "Documents used by the Kotlin binding smoke test.")

        val first = db.put("docs", """{"title":"alpha","body":"hello"}""")
        val second = db.putVec("docs", """{"title":"beta","body":"vector"}""", floatArrayOf(0.9f, 0.1f, 0.2f))

        checkState(db.getString(first)?.contains("alpha") == true, "get failed")
        checkState(db.queryString(first, "{ title }") == """{"title":"alpha"}""", "query failed")

        val batch = db.batchGet(listOf(first, second))
        checkState(batch.size == 2, "batch count failed")
        checkState(batch[1]?.decodeToString()?.contains("beta") == true, "batch value failed")

        val result = db.retrieve(floatArrayOf(1.0f, 0.0f, 0.0f), ring = "docs", budget = 5, topRings = 50, focus = 3)
        checkState(result.returned >= 1, "retrieve returned no hits")
        checkState(result.scanned >= result.returned, "retrieve stats inconsistent")

        val atlas = db.atlas(floatArrayOf(1.0f, 0.0f, 0.0f))
        checkState("galaxyMap" in atlas, "atlas missing galaxyMap")
        checkState("Documents used by the Kotlin binding smoke test." in atlas, "atlas missing ring description")

        val located = db.locate(first)
        checkState(located >= 0, "locate failed")
        checkState(db.nextVisit(first, located) >= 0.0, "nextVisit failed")
        checkState(db.nextJoin(first, second) >= -1.0, "nextJoin failed")
    }

    println("Kotlin driver OK")
}

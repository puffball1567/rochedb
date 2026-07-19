package org.orbeliasdb

import java.io.Closeable

data class OrbeliasId(
    val parent: Long,
    val epoch: Int,
    val seq: Int,
    val tWrite: Double,
)

data class OrbeliasHit(
    val id: OrbeliasId,
    val score: Double,
    val payload: ByteArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is OrbeliasHit) return false
        return id == other.id && score == other.score && payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + score.hashCode()
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

data class OrbeliasRetrieveResult(
    val hits: List<OrbeliasHit>,
    val totalVectors: Int,
    val scanned: Int,
    val skippedVectors: Int,
    val returned: Int,
    val ringsTouched: Int,
    val payloadBytes: Int,
    val estimatedTokens: Int,
    val fanoutNodes: Int,
    val candidateReduction: Double,
)

class OrbeliasDbException(message: String) : RuntimeException(message)

class OrbeliasDb private constructor(private var handle: Long) : Closeable {
    companion object {
        val abiVersion: Int
            get() = OrbeliasNative.abiVersion()

        fun open(nodes: Int = 8): OrbeliasDb = OrbeliasDb(OrbeliasNative.open(nodes))

        fun openDir(dir: String, nodes: Int = 8): OrbeliasDb = OrbeliasDb(OrbeliasNative.openDir(nodes, dir))

        fun connect(peers: String): OrbeliasDb = OrbeliasDb(OrbeliasNative.connect(peers))

        fun connectAuth(
            peers: String,
            username: String = "",
            password: String = "",
            authToken: String = "",
            secretKey: String = "",
            galaxy: String = "",
        ): OrbeliasDb = OrbeliasDb(OrbeliasNative.connectAuth(peers, username, password, authToken, secretKey, galaxy))
    }

    val now: Double
        get() = OrbeliasNative.now(checked())

    fun advance(dt: Double) = OrbeliasNative.advance(checked(), dt)

    fun configureRing(ring: String, period: Double) = OrbeliasNative.configureRing(checked(), ring, period)

    fun setGalaxyDescription(description: String) = OrbeliasNative.setGalaxyDescription(checked(), description)

    fun setRingDescription(ring: String, description: String) = OrbeliasNative.setRingDescription(checked(), ring, description)

    fun put(ring: String, payload: String): OrbeliasId = put(ring, payload.encodeToByteArray())

    fun put(ring: String, payload: ByteArray): OrbeliasId = OrbeliasNative.put(checked(), ring, payload)

    fun putVec(ring: String, payload: String, vector: FloatArray): OrbeliasId =
        putVec(ring, payload.encodeToByteArray(), vector)

    fun putVec(ring: String, payload: ByteArray, vector: FloatArray): OrbeliasId =
        OrbeliasNative.putVec(checked(), ring, payload, vector)

    fun get(id: OrbeliasId): ByteArray? = OrbeliasNative.get(checked(), id.parent, id.epoch, id.seq, id.tWrite)

    fun getString(id: OrbeliasId): String? = get(id)?.decodeToString()

    fun batchGet(ids: List<OrbeliasId>): List<ByteArray?> =
        OrbeliasNative.batchGet(
            checked(),
            ids.map { it.parent }.toLongArray(),
            ids.map { it.epoch }.toIntArray(),
            ids.map { it.seq }.toIntArray(),
            ids.map { it.tWrite }.toDoubleArray(),
        ).toList()

    fun query(id: OrbeliasId, selection: String): ByteArray? =
        OrbeliasNative.query(checked(), id.parent, id.epoch, id.seq, id.tWrite, selection)

    fun queryString(id: OrbeliasId, selection: String): String? = query(id, selection)?.decodeToString()

    fun retrieve(
        vector: FloatArray,
        ring: String = "",
        budget: Int = 10,
        topRings: Int = 50,
        focus: Int = 3,
    ): OrbeliasRetrieveResult = OrbeliasNative.retrieve(checked(), vector, ring, budget, topRings, focus)

    fun atlas(queryVector: FloatArray = floatArrayOf(), maxCentroidDims: Int = 8): String =
        OrbeliasNative.atlas(checked(), queryVector, maxCentroidDims)

    fun locate(id: OrbeliasId, at: Double = -1.0): Int =
        OrbeliasNative.locate(checked(), id.parent, id.epoch, id.seq, id.tWrite, at)

    fun nextVisit(id: OrbeliasId, node: Int): Double =
        OrbeliasNative.nextVisit(checked(), id.parent, id.epoch, id.seq, id.tWrite, node)

    fun nextJoin(a: OrbeliasId, b: OrbeliasId): Double =
        OrbeliasNative.nextJoin(
            checked(),
            a.parent,
            a.epoch,
            a.seq,
            a.tWrite,
            b.parent,
            b.epoch,
            b.seq,
            b.tWrite,
        )

    override fun close() {
        val h = handle
        if (h != 0L) {
            OrbeliasNative.close(h)
            handle = 0L
        }
    }

    private fun checked(): Long {
        if (handle == 0L) throw OrbeliasDbException("OrbeliasDB handle is closed")
        return handle
    }
}

internal object OrbeliasNative {
    init {
        System.loadLibrary("orbeliasdb_jni")
    }

    @JvmStatic external fun abiVersion(): Int
    @JvmStatic external fun open(nodes: Int): Long
    @JvmStatic external fun openDir(nodes: Int, dir: String): Long
    @JvmStatic external fun connect(peers: String): Long
    @JvmStatic external fun connectAuth(
        peers: String,
        username: String,
        password: String,
        authToken: String,
        secretKey: String,
        galaxy: String,
    ): Long
    @JvmStatic external fun close(handle: Long)
    @JvmStatic external fun now(handle: Long): Double
    @JvmStatic external fun advance(handle: Long, dt: Double)
    @JvmStatic external fun configureRing(handle: Long, ring: String, period: Double)
    @JvmStatic external fun setGalaxyDescription(handle: Long, description: String)
    @JvmStatic external fun setRingDescription(handle: Long, ring: String, description: String)
    @JvmStatic external fun put(handle: Long, ring: String, payload: ByteArray): OrbeliasId
    @JvmStatic external fun putVec(handle: Long, ring: String, payload: ByteArray, vector: FloatArray): OrbeliasId
    @JvmStatic external fun get(handle: Long, parent: Long, epoch: Int, seq: Int, tWrite: Double): ByteArray?
    @JvmStatic external fun batchGet(
        handle: Long,
        parents: LongArray,
        epochs: IntArray,
        seqs: IntArray,
        tWrites: DoubleArray,
    ): Array<ByteArray?>
    @JvmStatic external fun query(
        handle: Long,
        parent: Long,
        epoch: Int,
        seq: Int,
        tWrite: Double,
        selection: String,
    ): ByteArray?
    @JvmStatic external fun retrieve(
        handle: Long,
        vector: FloatArray,
        ring: String,
        budget: Int,
        topRings: Int,
        focus: Int,
    ): OrbeliasRetrieveResult
    @JvmStatic external fun atlas(handle: Long, queryVector: FloatArray, maxCentroidDims: Int): String
    @JvmStatic external fun locate(handle: Long, parent: Long, epoch: Int, seq: Int, tWrite: Double, at: Double): Int
    @JvmStatic external fun nextVisit(handle: Long, parent: Long, epoch: Int, seq: Int, tWrite: Double, node: Int): Double
    @JvmStatic external fun nextJoin(
        handle: Long,
        aParent: Long,
        aEpoch: Int,
        aSeq: Int,
        aTWrite: Double,
        bParent: Long,
        bEpoch: Int,
        bSeq: Int,
        bTWrite: Double,
    ): Double
}


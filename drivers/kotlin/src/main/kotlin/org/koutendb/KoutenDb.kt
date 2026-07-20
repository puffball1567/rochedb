package org.koutendb

import java.io.Closeable

data class KoutenId(
    val parent: Long,
    val epoch: Int,
    val seq: Int,
    val tWrite: Double,
)

data class KoutenHit(
    val id: KoutenId,
    val score: Double,
    val payload: ByteArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is KoutenHit) return false
        return id == other.id && score == other.score && payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + score.hashCode()
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

data class KoutenRetrieveResult(
    val hits: List<KoutenHit>,
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

class KoutenDbException(message: String) : RuntimeException(message)

class KoutenDb private constructor(private var handle: Long) : Closeable {
    companion object {
        val abiVersion: Int
            get() = KoutenNative.abiVersion()

        fun open(nodes: Int = 8): KoutenDb = KoutenDb(KoutenNative.open(nodes))

        fun openDir(dir: String, nodes: Int = 8): KoutenDb = KoutenDb(KoutenNative.openDir(nodes, dir))

        fun connect(peers: String): KoutenDb = KoutenDb(KoutenNative.connect(peers))

        fun connectAuth(
            peers: String,
            username: String = "",
            password: String = "",
            authToken: String = "",
            secretKey: String = "",
            galaxy: String = "",
        ): KoutenDb = KoutenDb(KoutenNative.connectAuth(peers, username, password, authToken, secretKey, galaxy))
    }

    val now: Double
        get() = KoutenNative.now(checked())

    fun advance(dt: Double) = KoutenNative.advance(checked(), dt)

    fun configureRing(ring: String, period: Double) = KoutenNative.configureRing(checked(), ring, period)

    fun setGalaxyDescription(description: String) = KoutenNative.setGalaxyDescription(checked(), description)

    fun setRingDescription(ring: String, description: String) = KoutenNative.setRingDescription(checked(), ring, description)

    fun put(ring: String, payload: String): KoutenId = put(ring, payload.encodeToByteArray())

    fun put(ring: String, payload: ByteArray): KoutenId = KoutenNative.put(checked(), ring, payload)

    fun putVec(ring: String, payload: String, vector: FloatArray): KoutenId =
        putVec(ring, payload.encodeToByteArray(), vector)

    fun putVec(ring: String, payload: ByteArray, vector: FloatArray): KoutenId =
        KoutenNative.putVec(checked(), ring, payload, vector)

    fun get(id: KoutenId): ByteArray? = KoutenNative.get(checked(), id.parent, id.epoch, id.seq, id.tWrite)

    fun getString(id: KoutenId): String? = get(id)?.decodeToString()

    fun batchGet(ids: List<KoutenId>): List<ByteArray?> =
        KoutenNative.batchGet(
            checked(),
            ids.map { it.parent }.toLongArray(),
            ids.map { it.epoch }.toIntArray(),
            ids.map { it.seq }.toIntArray(),
            ids.map { it.tWrite }.toDoubleArray(),
        ).toList()

    fun query(id: KoutenId, selection: String): ByteArray? =
        KoutenNative.query(checked(), id.parent, id.epoch, id.seq, id.tWrite, selection)

    fun queryString(id: KoutenId, selection: String): String? = query(id, selection)?.decodeToString()

    fun retrieve(
        vector: FloatArray,
        ring: String = "",
        budget: Int = 10,
        topRings: Int = 50,
        focus: Int = 3,
    ): KoutenRetrieveResult = KoutenNative.retrieve(checked(), vector, ring, budget, topRings, focus)

    fun atlas(queryVector: FloatArray = floatArrayOf(), maxCentroidDims: Int = 8): String =
        KoutenNative.atlas(checked(), queryVector, maxCentroidDims)

    fun locate(id: KoutenId, at: Double = -1.0): Int =
        KoutenNative.locate(checked(), id.parent, id.epoch, id.seq, id.tWrite, at)

    fun nextVisit(id: KoutenId, node: Int): Double =
        KoutenNative.nextVisit(checked(), id.parent, id.epoch, id.seq, id.tWrite, node)

    fun nextJoin(a: KoutenId, b: KoutenId): Double =
        KoutenNative.nextJoin(
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
            KoutenNative.close(h)
            handle = 0L
        }
    }

    private fun checked(): Long {
        if (handle == 0L) throw KoutenDbException("KoutenDB handle is closed")
        return handle
    }
}

internal object KoutenNative {
    init {
        System.loadLibrary("koutendb_jni")
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
    @JvmStatic external fun put(handle: Long, ring: String, payload: ByteArray): KoutenId
    @JvmStatic external fun putVec(handle: Long, ring: String, payload: ByteArray, vector: FloatArray): KoutenId
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
    ): KoutenRetrieveResult
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


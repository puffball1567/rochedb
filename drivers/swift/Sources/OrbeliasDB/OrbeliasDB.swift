import COrbeliasDB
import Foundation

public enum OrbeliasDBError: Error, CustomStringConvertible, Equatable {
    case abiVersionMismatch(expected: Int32, actual: Int32)
    case cAbi(String)
    case closed
    case invalidUtf8

    public var description: String {
        switch self {
        case let .abiVersionMismatch(expected, actual):
            return "OrbeliasDB ABI version mismatch: expected \(expected), got \(actual)"
        case let .cAbi(message):
            return message
        case .closed:
            return "OrbeliasDB handle is closed"
        case .invalidUtf8:
            return "OrbeliasDB returned invalid UTF-8"
        }
    }
}

public struct OrbeliasId: Equatable, Sendable {
    public let parent: UInt64
    public let epoch: UInt32
    public let seq: UInt32
    public let tWrite: Double

    public init(parent: UInt64, epoch: UInt32, seq: UInt32, tWrite: Double) {
        self.parent = parent
        self.epoch = epoch
        self.seq = seq
        self.tWrite = tWrite
    }
}

public struct OrbeliasHit: Equatable, Sendable {
    public let id: OrbeliasId
    public let score: Double
    public let payload: Data
}

public struct RetrieveStats: Equatable, Sendable {
    public let totalVectors: Int
    public let scanned: Int
    public let skippedVectors: Int
    public let returned: Int
    public let ringsTouched: Int
    public let payloadBytes: Int
    public let estimatedTokens: Int
    public let fanoutNodes: Int
    public let candidateReduction: Double
}

public struct RetrieveResult: Equatable, Sendable {
    public let hits: [OrbeliasHit]
    public let stats: RetrieveStats
}

public final class OrbeliasDB {
    public static let abiVersion: Int32 = 2
    private static let runtimeInit: Void = {
        orbelias_init()
    }()

    private var handle: UnsafeMutableRawPointer?

    private init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }

    deinit {
        close()
    }

    public static func open(nodes: Int32 = 8) throws -> OrbeliasDB {
        try ensureRuntime()
        guard let handle = orbelias_open(nodes) else {
            throw lastError()
        }
        return OrbeliasDB(handle: handle)
    }

    public static func openDir(nodes: Int32 = 8, dir: String) throws -> OrbeliasDB {
        try ensureRuntime()
        return try dir.withCString { cDir in
            guard let handle = orbelias_open_dir(nodes, cDir) else {
                throw lastError()
            }
            return OrbeliasDB(handle: handle)
        }
    }

    public static func connectAuth(
        peers: String,
        username: String = "",
        password: String = "",
        authToken: String = "",
        secretKey: String = "",
        galaxy: String = ""
    ) throws -> OrbeliasDB {
        try ensureRuntime()
        return try peers.withCString { cPeers in
            try username.withCString { cUsername in
                try password.withCString { cPassword in
                    try authToken.withCString { cAuthToken in
                        try secretKey.withCString { cSecretKey in
                            try galaxy.withCString { cGalaxy in
                                guard let handle = orbelias_connect_auth(
                                    cPeers,
                                    cUsername,
                                    cPassword,
                                    cAuthToken,
                                    cSecretKey,
                                    cGalaxy
                                ) else {
                                    throw lastError()
                                }
                                return OrbeliasDB(handle: handle)
                            }
                        }
                    }
                }
            }
        }
    }

    public static func connect(peers: String) throws -> OrbeliasDB {
        try connectAuth(peers: peers)
    }

    public func close() {
        if let handle {
            orbelias_close(handle)
            self.handle = nil
        }
    }

    public func configureRing(_ ring: String, period: Double) throws {
        try withHandle { handle in
            try ring.withCString { cRing in
                try check(orbelias_ring_configure(handle, cRing, period))
            }
        }
    }

    public func setGalaxyDescription(_ description: String) throws {
        try withHandle { handle in
            try description.withCString { cDescription in
                try check(orbelias_set_galaxy_description(handle, cDescription))
            }
        }
    }

    public func setRingDescription(_ ring: String, description: String) throws {
        try withHandle { handle in
            try ring.withCString { cRing in
                try description.withCString { cDescription in
                    try check(orbelias_set_ring_description(handle, cRing, cDescription))
                }
            }
        }
    }

    public func put(_ ring: String, payload: Data) throws -> OrbeliasId {
        try withHandle { handle in
            try ring.withCString { cRing in
                var id = orbelias_id()
                let rc = payload.withUnsafeBytes { bytes in
                    orbelias_put(handle, cRing, bytes.baseAddress, payload.count, &id)
                }
                try check(rc)
                return OrbeliasId(c: id)
            }
        }
    }

    public func put(_ ring: String, payload: String) throws -> OrbeliasId {
        try put(ring, payload: Data(payload.utf8))
    }

    public func putVec(_ ring: String, payload: Data, vector: [Float]) throws -> OrbeliasId {
        try withHandle { handle in
            try ring.withCString { cRing in
                var id = orbelias_id()
                let rc = payload.withUnsafeBytes { payloadBytes in
                    vector.withUnsafeBufferPointer { vectorBytes in
                        orbelias_put_vec(
                            handle,
                            cRing,
                            payloadBytes.baseAddress,
                            payload.count,
                            vectorBytes.baseAddress,
                            vector.count,
                            &id
                        )
                    }
                }
                try check(rc)
                return OrbeliasId(c: id)
            }
        }
    }

    public func putVec(_ ring: String, payload: String, vector: [Float]) throws -> OrbeliasId {
        try putVec(ring, payload: Data(payload.utf8), vector: vector)
    }

    public func get(_ id: OrbeliasId) throws -> Data? {
        try withHandle { handle in
            var len = 0
            guard let ptr = orbelias_get(handle, id.cValue, &len) else {
                let err = Self.lastError()
                if case let .cAbi(message) = err, message.contains("not found") {
                    return nil
                }
                throw err
            }
            defer { orbelias_free(ptr) }
            return Data(bytes: ptr, count: len)
        }
    }

    public func getString(_ id: OrbeliasId) throws -> String? {
        guard let data = try get(id) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw OrbeliasDBError.invalidUtf8
        }
        return value
    }

    public func batchGet(_ ids: [OrbeliasId]) throws -> [Data] {
        try withHandle { handle in
            var rawIds = ids.map(\.cValue)
            let count = rawIds.count
            let result = rawIds.withUnsafeMutableBufferPointer { buffer in
                orbelias_batch_get(handle, buffer.baseAddress, count)
            }
            guard let result else {
                throw Self.lastError()
            }
            defer { orbelias_batch_get_free(result) }
            guard let values = result.pointee.values else {
                return []
            }
            return (0..<Int(result.pointee.len)).map { index in
                let value = values.advanced(by: index).pointee
                guard let data = value.data, value.len > 0 else {
                    return Data()
                }
                return Data(bytes: data, count: value.len)
            }
        }
    }

    public func query(_ id: OrbeliasId, selection: String) throws -> Data {
        try withHandle { handle in
            try selection.withCString { cSelection in
                var len = 0
                guard let ptr = orbelias_query(handle, id.cValue, cSelection, &len) else {
                    throw Self.lastError()
                }
                defer { orbelias_free(ptr) }
                return Data(bytes: ptr, count: len)
            }
        }
    }

    public func queryString(_ id: OrbeliasId, selection: String) throws -> String {
        let data = try query(id, selection: selection)
        guard let value = String(data: data, encoding: .utf8) else {
            throw OrbeliasDBError.invalidUtf8
        }
        return value
    }

    public func retrieve(
        vector: [Float],
        ring: String = "",
        budget: Int32 = 8,
        topRings: Int32 = 0,
        focus: Int32 = 0
    ) throws -> RetrieveResult {
        try withHandle { handle in
            try ring.withCString { cRing in
                let result = vector.withUnsafeBufferPointer { vectorBytes in
                    orbelias_retrieve(
                        handle,
                        vectorBytes.baseAddress,
                        vector.count,
                        cRing,
                        budget,
                        topRings,
                        focus
                    )
                }
                guard let result else {
                    throw Self.lastError()
                }
                defer { orbelias_retrieve_free(result) }
                let raw = result.pointee
                let hits: [OrbeliasHit]
                if let rawHits = raw.hits {
                    hits = (0..<Int(raw.len)).map { index in
                        let hit = rawHits.advanced(by: index).pointee
                        let payload: Data
                        if let ptr = hit.payload, hit.payload_len > 0 {
                            payload = Data(bytes: ptr, count: hit.payload_len)
                        } else {
                            payload = Data()
                        }
                        return OrbeliasHit(id: OrbeliasId(c: hit.id), score: hit.score, payload: payload)
                    }
                } else {
                    hits = []
                }
                return RetrieveResult(
                    hits: hits,
                    stats: RetrieveStats(
                        totalVectors: Int(raw.total_vectors),
                        scanned: Int(raw.scanned),
                        skippedVectors: Int(raw.skipped_vectors),
                        returned: Int(raw.returned),
                        ringsTouched: Int(raw.rings_touched),
                        payloadBytes: Int(raw.payload_bytes),
                        estimatedTokens: Int(raw.estimated_tokens),
                        fanoutNodes: Int(raw.fanout_nodes),
                        candidateReduction: raw.candidate_reduction
                    )
                )
            }
        }
    }

    public func atlas(queryVector: [Float] = [], maxCentroidDims: Int32 = 8) throws -> String {
        try withHandle { handle in
            var len = 0
            let ptr = queryVector.withUnsafeBufferPointer { buffer in
                orbelias_atlas(handle, buffer.baseAddress, queryVector.count, maxCentroidDims, &len)
            }
            guard let ptr else {
                throw Self.lastError()
            }
            defer { orbelias_free(ptr) }
            guard let value = String(data: Data(bytes: ptr, count: len), encoding: .utf8) else {
                throw OrbeliasDBError.invalidUtf8
            }
            return value
        }
    }

    public func locate(_ id: OrbeliasId, at: Double = -1.0) throws -> Int {
        try withHandle { handle in
            let node = orbelias_locate(handle, id.cValue, at)
            if node < 0 {
                throw Self.lastError()
            }
            return Int(node)
        }
    }

    public func nextVisit(_ id: OrbeliasId, node: Int32) throws -> Double {
        try withHandle { handle in
            let time = orbelias_next_visit(handle, id.cValue, node)
            if time < 0 {
                throw Self.lastError()
            }
            return time
        }
    }

    public func nextJoin(_ a: OrbeliasId, _ b: OrbeliasId) throws -> Double? {
        try withHandle { handle in
            let time = orbelias_next_join(handle, a.cValue, b.cValue)
            return time < 0 ? nil : time
        }
    }

    private static func ensureRuntime() throws {
        _ = runtimeInit
        let actual = orbelias_abi_version()
        if actual != abiVersion {
            throw OrbeliasDBError.abiVersionMismatch(expected: abiVersion, actual: actual)
        }
    }

    private static func lastError() -> OrbeliasDBError {
        guard let ptr = orbelias_last_error() else {
            return .cAbi("OrbeliasDB C ABI error")
        }
        let message = String(cString: ptr)
        return .cAbi(message.isEmpty ? "OrbeliasDB C ABI error" : message)
    }

    private func withHandle<T>(_ body: (UnsafeMutableRawPointer) throws -> T) throws -> T {
        guard let handle else {
            throw OrbeliasDBError.closed
        }
        return try body(handle)
    }

    private func check(_ code: Int32) throws {
        if code != ORBELIAS_OK {
            throw Self.lastError()
        }
    }
}

private extension OrbeliasId {
    init(c: orbelias_id) {
        self.init(parent: c.parent, epoch: c.epoch, seq: c.seq, tWrite: c.t_write)
    }

    var cValue: orbelias_id {
        orbelias_id(parent: parent, epoch: epoch, seq: seq, t_write: tWrite)
    }
}

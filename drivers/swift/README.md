# RocheDB Swift Driver

Minimal Swift Package wrapper over the RocheDB C ABI.

```swift
import RocheDB

let db = try RocheDB.open(nodes: 8)
defer { db.close() }

try db.setGalaxyDescription("Product and support knowledge")
try db.setRingDescription("docs", description: "Documentation ring")

let id = try db.putVec("docs", payload: "hello", vector: [1.0, 0.0])
let value = try db.getString(id)
let atlas = try db.atlas(queryVector: [1.0, 0.0], maxCentroidDims: 8)
```

Build the RocheDB shared library first:

```bash
scripts/build_capi.sh
drivers/swift/docker-test.sh
```

Linux tests cover the generic Swift C ABI wrapper. iOS/macOS app lifecycle, sandbox paths,
XCFramework packaging, and SwiftUI/UIKit integration still need Apple-platform validation.

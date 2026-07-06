# Package

version       = "0.1.3"
author        = "puffball1567"
description   = "RocheDB PoC - ephemeris-based distributed document/vector store"
license       = "Apache-2.0"
srcDir        = "src"
bin           = @["rochesim", "rochebench", "roched", "rochecli"]

# Dependencies

requires "nim >= 2.0.0"
requires "nimsodium >= 0.2.0"

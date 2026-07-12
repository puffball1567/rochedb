# Package

version     = "0.3.0"
author      = "puffball1567"
description = "Ring-oriented NoSQL document/vector store for smaller working sets"
license     = "Apache-2.0"
srcDir      = "src"
bin         = @["roche", "rochecli", "roched", "rochebench", "rochesim"]

# Dependencies

requires "nim >= 2.0.0"
requires "nimsodium >= 0.2.0"

task test, "Run the embedded RocheDB test suite":
  exec "scripts/test_core.sh"

task smoke, "Run the RocheDB smoke suite":
  exec "scripts/test_all_smoke.sh"

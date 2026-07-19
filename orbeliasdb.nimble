# Package

version     = "0.7.0"
author      = "puffball1567"
description = "OrbeliasDB: ring-oriented NoSQL document/vector store for smaller working sets"
license     = "Apache-2.0"
srcDir      = "src"
bin         = @["orbelias", "orbeliascli", "orbeliasd", "orbeliasbench", "orbeliassim"]

# Dependencies

requires "nim >= 2.0.0"
requires "nimsodium >= 0.2.0"

task test, "Run the embedded OrbeliasDB test suite":
  exec "scripts/test_core.sh"

task smoke, "Run the OrbeliasDB smoke suite":
  exec "scripts/test_all_smoke.sh"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DOCKER="${ROCHE_COMPAT_DOCKER:-0}"
RUN_WIRE="${ROCHE_COMPAT_WIRE:-1}"

log() {
  printf '\n[compat] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[compat] skip: %s is not installed\n' "$1"
    return 1
  fi
}

cd "$ROOT"

log "build C ABI shared library"
nim c --app:lib -d:release --nimcache:/tmp/nimcache_roche_capi -o:lib/librochedb.so src/rochedb_capi.nim

log "build roched for wire-driver tests"
nim c -d:release --nimcache:/tmp/nimcache_roched -o:src/roched src/roched.nim

log "C ABI contract"
mkdir -p bin
gcc examples/cabi_contract.c -Iinclude -Llib -lrochedb -Wl,-rpath,'$ORIGIN/../lib' -o bin/cabi_contract
LD_LIBRARY_PATH=lib bin/cabi_contract

log "C++ driver"
g++ -std=c++17 -Iinclude -Idrivers/cpp/include drivers/cpp/examples/contract_smoke.cpp -Llib -lrochedb -o /tmp/roche_cpp_contract_smoke
LD_LIBRARY_PATH=lib /tmp/roche_cpp_contract_smoke

if require_cmd dotnet; then
  log "C# driver"
  DOTNET_CLI_HOME="${DOTNET_CLI_HOME:-/tmp/dotnet-home}" \
  DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
  dotnet run --project drivers/csharp/ContractSmoke/ContractSmoke.csproj
fi

if require_cmd cargo; then
  log "Rust driver"
  printf '[compat] skip: Rust driver is split out of the core repository\n'
fi

if require_cmd go; then
  log "Go driver"
  (cd drivers/go && GOCACHE="${GOCACHE:-/tmp/roche-go-cache}" go test ./...)
fi

if [[ "$RUN_WIRE" == "1" ]]; then
  if require_cmd python3; then
    log "Python native wire driver"
    python3 drivers/python/tests/test_driver.py
  fi

  if require_cmd node; then
    log "Node.js native wire driver"
    node --test drivers/node/test/*.test.js
  fi

  if require_cmd bun; then
    log "Bun native wire driver"
    bun test drivers/node/test-bun/*.test.ts
  else
    printf '[compat] skip: bun is not installed\n'
  fi

  log "Nim wire protocol driver"
  nim c --nimcache:/tmp/nimcache_roche_twire_driver -r tests/twire_driver.nim
else
  log "wire-driver tests skipped because ROCHE_COMPAT_WIRE=$RUN_WIRE"
fi

if [[ "$RUN_DOCKER" == "1" ]]; then
  log "PHP driver via Docker"
  drivers/php/docker-test.sh

  log "Swift driver via Docker"
  drivers/swift/docker-test.sh

  log "Kotlin driver via Docker"
  drivers/kotlin/docker-test.sh
else
  log "Docker-backed PHP / Swift / Kotlin tests skipped; set ROCHE_COMPAT_DOCKER=1 to run them"
fi

log "driver compatibility suite OK"

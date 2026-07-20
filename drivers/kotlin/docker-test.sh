#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${KOTLIN_IMAGE:-koutendb-kotlin:2.0.21-jdk21}"

if [[ "${KOTLIN_REBUILD:-0}" == "1" ]] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" "$ROOT/drivers/kotlin"
fi

docker run --rm \
  -v "$ROOT:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    g++ -std=c++17 -fPIC -shared \
      -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" -I/work/include \
      /work/drivers/kotlin/native/koutendb_jni.cpp \
      -L/work/lib -lkoutendb \
      -Wl,-rpath,/work/lib \
      -o /tmp/libkoutendb_jni.so
    kotlinc \
      /work/drivers/kotlin/src/main/kotlin/org/koutendb/KoutenDb.kt \
      /work/drivers/kotlin/smoke/ContractSmoke.kt \
      -include-runtime \
      -d /tmp/koutendb-kotlin-smoke.jar
    LD_LIBRARY_PATH=/tmp:/work/lib java -Djava.library.path=/tmp:/work/lib -jar /tmp/koutendb-kotlin-smoke.jar
  '

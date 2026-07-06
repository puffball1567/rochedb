#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY_TOOLS="${ROOT}/.tools/python"

mkdir -p "${PY_TOOLS}"

python3 -m pip install --upgrade --target "${PY_TOOLS}" cmake ninja

echo "installed Python build tools under ${PY_TOOLS}"
echo "build_faiss_bridge.sh will automatically use this CMake package"

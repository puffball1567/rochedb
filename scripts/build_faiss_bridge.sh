#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/lib/liborbelias_faiss.so"
SRC="${ROOT}/src/orbelias/faiss_bridge.cpp"
FAISS_SRC="${ROOT}/third_party/faiss"
FAISS_BUILD="${FAISS_SRC}/build"
PY_TOOLS="${ROOT}/.tools/python"

run_cmake() {
  if [[ -n "${ORBELIAS_CMAKE:-}" ]]; then
    "${ORBELIAS_CMAKE}" "$@"
  elif [[ -d "${PY_TOOLS}" ]]; then
    PYTHONPATH="${PY_TOOLS}:${PYTHONPATH:-}" python3 -m cmake "$@"
  else
    cmake "$@"
  fi
}

find_ldconfig_lib() {
  local name="$1"
  ldconfig -p 2>/dev/null | awk -v n="${name}" '$1 == n { print $NF; exit }'
}

mkdir -p "${ROOT}/lib"

pkg_flags=()
if pkg-config --exists faiss; then
  # shellcheck disable=SC2207
  pkg_flags=($(pkg-config --cflags --libs faiss))
elif [[ -d "${FAISS_SRC}" ]]; then
  if [[ ! -f "${FAISS_BUILD}/faiss/libfaiss.so" && ! -f "${FAISS_BUILD}/faiss/libfaiss.a" ]]; then
    blas_libs="${ORBELIAS_BLAS_LIBRARIES:-$(find_ldconfig_lib libopenblas.so.0)}"
    if [[ -z "${blas_libs}" ]]; then
      blas_libs="${ORBELIAS_BLAS_LIBRARIES:-$(find_ldconfig_lib libblas.so.3)}"
    fi
    lapack_libs="${ORBELIAS_LAPACK_LIBRARIES:-$(find_ldconfig_lib liblapack.so.3)}"
    if [[ -z "${lapack_libs}" ]]; then
      lapack_libs="${ORBELIAS_LAPACK_LIBRARIES:-$(find_ldconfig_lib liblapack_atlas.so.3)}"
    fi
    if [[ -z "${blas_libs}" || -z "${lapack_libs}" ]]; then
      echo "FAISS requires BLAS/LAPACK. Install OpenBLAS/LAPACK dev packages or set:" >&2
      echo "  ORBELIAS_BLAS_LIBRARIES=/path/to/libblas.so" >&2
      echo "  ORBELIAS_LAPACK_LIBRARIES=/path/to/liblapack.so" >&2
      exit 1
    fi
    run_cmake -S "${FAISS_SRC}" -B "${FAISS_BUILD}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DFAISS_ENABLE_MKL=OFF \
      -DFAISS_ENABLE_GPU=OFF \
      -DFAISS_ENABLE_PYTHON=OFF \
      -DFAISS_ENABLE_C_API=OFF \
      -DBUILD_TESTING=OFF \
      -DBLAS_LIBRARIES="${blas_libs}" \
      -DLAPACK_LIBRARIES="${lapack_libs}"
    run_cmake --build "${FAISS_BUILD}" --target faiss --parallel
  fi
  pkg_flags=(
    "-I${FAISS_SRC}"
    "-L${FAISS_BUILD}/faiss"
    "-lfaiss"
    "-Wl,-rpath,${FAISS_BUILD}/faiss"
  )
else
  echo "FAISS was not found via pkg-config and ${FAISS_SRC} does not exist." >&2
  echo "Run scripts/fetch_faiss.sh first, or install FAISS development files." >&2
  exit 1
fi

g++ -std=c++17 -O3 -fPIC -shared "${SRC}" -o "${OUT}" "${pkg_flags[@]}"

echo "built ${OUT}"

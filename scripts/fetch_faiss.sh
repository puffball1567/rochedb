#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${ROCHE_FAISS_VERSION:-v1.14.3}"
PINNED_COMMIT="${ROCHE_FAISS_COMMIT:-}"
URL="${ROCHE_FAISS_URL:-https://github.com/facebookresearch/faiss.git}"
DEST="${ROOT}/third_party/faiss"

mkdir -p "${ROOT}/third_party"

if [[ -d "${DEST}/.git" ]]; then
  echo "[faiss] updating existing checkout at ${DEST}"
  git -C "${DEST}" fetch --tags --depth 1 origin "${VERSION}"
  git -C "${DEST}" checkout --detach "FETCH_HEAD"
else
  if [[ -e "${DEST}" ]]; then
    echo "[faiss] ${DEST} exists but is not a git checkout" >&2
    exit 1
  fi
  echo "[faiss] cloning ${URL} ${VERSION} into ${DEST}"
  git clone --depth 1 --branch "${VERSION}" "${URL}" "${DEST}"
fi

ACTUAL_COMMIT="$(git -C "${DEST}" rev-parse HEAD)"
if [[ -n "${PINNED_COMMIT}" && "${ACTUAL_COMMIT}" != "${PINNED_COMMIT}" ]]; then
  echo "[faiss] fetched ${VERSION} @ ${ACTUAL_COMMIT}" >&2
  echo "[faiss] expected pinned commit ${PINNED_COMMIT}" >&2
  exit 1
fi

printf '%s\n' "${ACTUAL_COMMIT}" > "${ROOT}/third_party/faiss.version"
if [[ -n "${PINNED_COMMIT}" ]]; then
  echo "[faiss] fetched pinned ${VERSION} @ ${ACTUAL_COMMIT}"
else
  echo "[faiss] fetched ${VERSION} @ ${ACTUAL_COMMIT}"
fi

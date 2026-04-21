#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build/pyinstaller"
DIST_DIR="${ROOT_DIR}/binary-dist"
BINARY_NAME="aicodex-ai-gateway"
BUILD_MODE="onefile"
PYTHON_BIN=""
SKIP_SYNC=0
KEEP_BUILD=0
DRY_RUN=0
UV_CMD=(uvx --from "uv==0.10.9" uv)
PRISMA_CACHE_DIR="${BUILD_DIR}/prisma-cache"
NPM_CACHE_DIR="${BUILD_DIR}/npm-cache"

usage() {
  cat <<'EOF'
Usage: ./build_binary.sh [options]

Build a self-contained LiteLLM proxy executable for the current OS/arch.

Options:
  --mode <onefile|onedir>  Build mode. Default: onefile
  --name <binary-name>     Output binary name. Default: aicodex-ai-gateway
  --dist-dir <dir>         Output directory. Default: ./binary-dist
  --build-dir <dir>        PyInstaller work directory. Default: ./build/pyinstaller
  --python <python-bin>    Python interpreter passed to uv sync
  --skip-sync              Skip `uv sync` before building
  --keep-build             Keep PyInstaller work files
  --dry-run                Print the resolved build command and exit
  -h, --help               Show this help

Examples:
  ./build_binary.sh
  ./build_binary.sh --mode onedir --name litellm-proxy-debug
  ./build_binary.sh --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      BUILD_MODE="${2:-}"
      shift 2
      ;;
    --name)
      BINARY_NAME="${2:-}"
      shift 2
      ;;
    --dist-dir)
      DIST_DIR="${2:-}"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="${2:-}"
      shift 2
      ;;
    --python)
      PYTHON_BIN="${2:-}"
      shift 2
      ;;
    --skip-sync)
      SKIP_SYNC=1
      shift
      ;;
    --keep-build)
      KEEP_BUILD=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${BUILD_MODE}" != "onefile" && "${BUILD_MODE}" != "onedir" ]]; then
  echo "Invalid --mode: ${BUILD_MODE}" >&2
  exit 1
fi

if [[ ${DRY_RUN} -eq 1 ]]; then
  SKIP_SYNC=1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for bundling Prisma CLI but was not found in PATH." >&2
  exit 1
fi

NODE_BIN="$(command -v node)"

if [[ ${SKIP_SYNC} -eq 0 ]]; then
  SYNC_CMD=("${UV_CMD[@]}" sync --frozen --group proxy-dev --extra proxy --extra proxy-runtime --extra extra_proxy)
  if [[ -n "${PYTHON_BIN}" ]]; then
    SYNC_CMD+=(--python "${PYTHON_BIN}")
  fi
  echo "==> Syncing build dependencies"
  (
    cd "${ROOT_DIR}"
    "${SYNC_CMD[@]}"
  )
fi

if [[ ${DRY_RUN} -eq 0 ]]; then
  if [[ ! -x "${ROOT_DIR}/.venv/bin/python" ]]; then
    echo "Expected virtual environment at ${ROOT_DIR}/.venv after uv sync." >&2
    exit 1
  fi

  if ! "${ROOT_DIR}/.venv/bin/python" -c 'import prisma' >/dev/null 2>&1; then
    echo "Expected Prisma Python package to be installed in ${ROOT_DIR}/.venv." >&2
    exit 1
  fi

  echo "==> Warming Prisma CLI cache"
  mkdir -p "${PRISMA_CACHE_DIR}" "${NPM_CACHE_DIR}"
  PRISMA_BINARY_CACHE_DIR="${PRISMA_CACHE_DIR}" \
  PRISMA_USE_GLOBAL_NODE=true \
  NPM_CONFIG_CACHE="${NPM_CACHE_DIR}" \
  "${ROOT_DIR}/.venv/bin/python" - <<'PY'
from prisma.cli.prisma import ensure_cached

cache = ensure_cached()
print(cache.entrypoint)
PY
fi

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

PYINSTALLER_ARGS=(
  --noconfirm
  --clean
  --paths "${ROOT_DIR}"
  --distpath "${DIST_DIR}"
  --workpath "${BUILD_DIR}/work"
  --specpath "${BUILD_DIR}/spec"
  --name "${BINARY_NAME}"
  --runtime-hook "${ROOT_DIR}/scripts/pyinstaller_runtime_hook.py"
  --add-binary "${NODE_BIN}:bin"
  --add-data "${PRISMA_CACHE_DIR}:prisma-cache"
  --collect-all litellm
  --collect-all litellm_proxy_extras
  --collect-all litellm_enterprise
  --collect-all prisma
  --collect-all tiktoken
  --collect-submodules tiktoken_ext
  --hidden-import tiktoken_ext.openai_public
  --copy-metadata litellm
  --copy-metadata prisma
)

if [[ "${BUILD_MODE}" == "onefile" ]]; then
  PYINSTALLER_ARGS+=(--onefile)
else
  PYINSTALLER_ARGS+=(--onedir)
fi

ENTRYPOINT="${ROOT_DIR}/scripts/binary_entrypoint.py"
PYINSTALLER_CMD=("${UV_CMD[@]}" run --with pyinstaller==6.16.0 pyinstaller "${PYINSTALLER_ARGS[@]}" "${ENTRYPOINT}")

if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "==> Dry run"
  printf '%q ' "${PYINSTALLER_CMD[@]}"
  printf '\n'
  exit 0
fi

echo "==> Building ${BINARY_NAME} (${BUILD_MODE})"
(
  cd "${ROOT_DIR}"
  "${PYINSTALLER_CMD[@]}"
)

if [[ ${KEEP_BUILD} -eq 0 ]]; then
  rm -rf "${BUILD_DIR}/work" "${BUILD_DIR}/spec"
fi

if [[ "${BUILD_MODE}" == "onefile" ]]; then
  echo "==> Binary ready: ${DIST_DIR}/${BINARY_NAME}"
else
  echo "==> Bundle ready: ${DIST_DIR}/${BINARY_NAME}"
fi

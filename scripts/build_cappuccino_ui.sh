#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UI_DIR="${REPO_ROOT}/ATProtoPDS/Sources/App/CappuccinoUI"
CONFIG="${1:-Release}"

if [[ ! -d "${UI_DIR}" ]]; then
  echo "Cappuccino UI directory not found: ${UI_DIR}" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to build Cappuccino UI." >&2
  exit 1
fi

echo "[cappuccino-ui] installing npm dependencies..."
cd "${UI_DIR}"
npm install --no-audit --no-fund

if [[ ! -d "${UI_DIR}/Frameworks/Objective-J" ]]; then
  echo "[cappuccino-ui] generating Frameworks..."
  npm run frameworks
fi

echo "[cappuccino-ui] building (${CONFIG})..."
if [[ "${CONFIG}" == "Debug" ]]; then
  npm run build:debug
else
  npm run build:release
fi

APP_PATH="${UI_DIR}/Build/${CONFIG}/CappuccinoUI"
DIST_PATH="${UI_DIR}/dist/CappuccinoUI"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected build output not found: ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${UI_DIR}/dist"
rm -rf "${DIST_PATH}"
cp -R "${APP_PATH}" "${DIST_PATH}"

echo "[cappuccino-ui] staged output at ${DIST_PATH}"

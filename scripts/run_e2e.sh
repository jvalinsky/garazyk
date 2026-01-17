#!/bin/bash
set -euo pipefail

DATA_DIR="$(mktemp -d -t objpds-e2e-data.XXXXXX)"
LOG_DIR="$(mktemp -d -t objpds-e2e-logs.XXXXXX)"
CONFIG_PATH="$(mktemp -t objpds-e2e-config.XXXXXX.json)"
PDS_LOG="${LOG_DIR}/pds.log"
PLC_LOG="${LOG_DIR}/plc.log"

cat > "${CONFIG_PATH}" <<EOF
{"server":{"data_dir":"${DATA_DIR}","host":"localhost"},"plc":{"url":"http://localhost:2582"}}
EOF

# Ensure cleanup on exit
cleanup() {
    status=$?
    echo "[E2E] Cleaning up..."
    if [ -n "${SERVER_PID:-}" ]; then
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
    if [ -n "${PLC_PID:-}" ]; then
        kill "${PLC_PID}" 2>/dev/null || true
        wait "${PLC_PID}" 2>/dev/null || true
    fi
    rm -rf "${DATA_DIR}"
    if [ "$status" -eq 0 ]; then
        rm -rf "${LOG_DIR}"
    else
        echo "[E2E] Logs preserved at ${LOG_DIR}"
    fi
    rm -f "${CONFIG_PATH}"
    exit "$status"
}
trap cleanup EXIT INT TERM

# Build the project
echo "[E2E] Building project..."
cmake --build build --target september atproto-plc || exit 1

# Start PLC server in background
echo "[E2E] Starting PLC server..."
./build/bin/atproto-plc > "${PLC_LOG}" 2>&1 &
PLC_PID=$!
sleep 2

# Start PDS server in background
echo "[E2E] Starting PDS server..."
./build/bin/september --config "${CONFIG_PATH}" serve --port 2583 --data-dir "${DATA_DIR}" > "${PDS_LOG}" 2>&1 &
SERVER_PID=$!

# Wait for servers to be ready
echo "[E2E] Waiting for servers..."
sleep 5

# Create test accounts
echo "[E2E] Creating test accounts..."
./build/bin/september --config "${CONFIG_PATH}" account create \
    --handle e2e1.test \
    --email e2e1@test.com \
    --password hunter2 \
    --data-dir "${DATA_DIR}" \
    --verbose || {
        echo "[E2E] Failed to create test account e2e1.test. Checking logs..."
        echo "=== PDS LOG ==="
        tail -n 20 "${PDS_LOG}"
        echo "=== PLC LOG ==="
        tail -n 20 "${PLC_LOG}"
        exit 1
    }

./build/bin/september --config "${CONFIG_PATH}" account create \
    --handle e2e2.test \
    --email e2e2@test.com \
    --password hunter2 \
    --data-dir "${DATA_DIR}" \
    --verbose || {
        echo "[E2E] Failed to create test account e2e2.test. Checking logs..."
        echo "=== PDS LOG ==="
        tail -n 20 "${PDS_LOG}"
        echo "=== PLC LOG ==="
        tail -n 20 "${PLC_LOG}"
        exit 1
    }

echo "[E2E] Running Puppeteer tests..."
npm --prefix Tests/e2e test

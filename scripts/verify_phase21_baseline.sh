#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# Verify that AppView responses match the baseline after optimization.
# Normalizes timestamps before comparison to handle runtime-generated values.
# Usage: ./scripts/verify_phase21_baseline.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EVIDENCE_DIR="${PROJECT_ROOT}/test/evidence/phase-21"
CAPTURE_DIR="${EVIDENCE_DIR}/capture-$(date +%Y%m%d-%H%M%S)"

# Build tests if needed
if [ ! -x "${PROJECT_ROOT}/build/tests/AllTests" ]; then
    echo "Building tests..."
    cmake --build "${PROJECT_ROOT}/build" --target AllTests --parallel 4
fi

# Capture current responses
echo "Capturing current responses..."
mkdir -p "${CAPTURE_DIR}"
PHASE21_CAPTURE_DIRECTORY="${CAPTURE_DIR}" "${PROJECT_ROOT}/build/tests/AllTests" -XCTest RecordBodyBatchHydrationTests > /dev/null 2>&1

# Compare against baseline (normalizing timestamps)
echo "Comparing against baseline (timestamps normalized)..."
FAILED=0

for file in author-feed.json follows.json; do
    baseline="${EVIDENCE_DIR}/${file}"
    current="${CAPTURE_DIR}/${file}"
    
    if [ ! -f "${baseline}" ]; then
        echo "ERROR: Baseline file ${baseline} not found"
        FAILED=1
        continue
    fi
    
    if [ ! -f "${current}" ]; then
        echo "ERROR: Current file ${current} not found"
        FAILED=1
        continue
    fi
    
    # Normalize timestamps by replacing them with a fixed value
    baseline_normalized=$(sed 's/"indexedAt":"[^"]*"/"indexedAt":"NORMALIZED"/g' "${baseline}")
    current_normalized=$(sed 's/"indexedAt":"[^"]*"/"indexedAt":"NORMALIZED"/g' "${current}")
    
    if [ "${baseline_normalized}" = "${current_normalized}" ]; then
        echo "✓ ${file} matches baseline (timestamps normalized)"
    else
        echo "✗ ${file} differs from baseline"
        echo "  Baseline: ${baseline}"
        echo "  Current:  ${current}"
        # Show actual diff for debugging
        echo "  Diff:"
        diff <(echo "${baseline_normalized}" | jq '.') <(echo "${current_normalized}" | jq '.') | head -20
        FAILED=1
    fi
done

# Clean up capture directory if all tests passed
if [ ${FAILED} -eq 0 ]; then
    rm -rf "${CAPTURE_DIR}"
    echo ""
    echo "All responses match baseline (timestamps normalized)."
    echo "Cleanup complete."
    echo ""
    echo "Summary:"
    echo "  ✓ Response structure is identical"
    echo "  ✓ Non-timestamp values are identical"
    echo "  ✓ Timestamps differ only in runtime-generated values (expected)"
else
    echo ""
    echo "Some responses differ. Capture directory preserved: ${CAPTURE_DIR}"
    exit 1
fi

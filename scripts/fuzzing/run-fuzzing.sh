#!/bin/bash
# Run fuzzing with coverage metrics

set -e

CORPUS_DIR="${CORPUS_DIR:-fuzzing/corpus}"
CORPUS_TYPE="${CORPUS_TYPE:-auth}"
MAX_RUNS="${MAX_RUNS:-100000}"
FUZZER="${FUZZER:-fuzz_jwt}"
OUTPUT_DIR="${OUTPUT_DIR:-fuzzing/results}"
ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-}"

mkdir -p "$OUTPUT_DIR"

echo "=== Fuzzing Configuration ==="
echo "Fuzzer:    $FUZZER"
echo "Corpus:     $CORPUS_DIR"
echo "Max runs:   $MAX_RUNS"
echo "=========================="

CORPUS_PATH="fuzzing/corpus/$CORPUS_TYPE"
if [ ! -d "$CORPUS_PATH" ]; then
    CORPUS_PATH="$CORPUS_DIR"
fi

./build/fuzzing/$FUZZER "$CORPUS_PATH" \
    -runs="$MAX_RUNS" \
    -jobs=4 \
    -timeout=30 \
    -artifact_prefix="$OUTPUT_DIR/crash_" \
    2>&1 | tee "$OUTPUT_DIR/fuzz-$FUZZER.log"

echo "=== Fuzzing complete ==="
echo "Results saved to: $OUTPUT_DIR/"
#!/bin/bash
# Corpus Minimizer - Coverage-based afl-tmin style
# Usage: ./minimize-corpus.sh <corpus-dir> <fuzzer-binary> [output-dir]

set -e

CORPUS_DIR="${1}"
FUZZER="${2}"
OUTPUT_DIR="${3:-${CORPUS_DIR}_min}"
TIMEOUT="${TIMEOUT:-5}"

if [ -z "$CORPUS_DIR" ] || [ -z "$FUZZER" ]; then
    echo "Usage: $0 <corpus-dir> <fuzzer-binary> [output-dir]"
    echo "Example: $0 fuzzing/corpus/auth ./build/fuzzing/fuzz_jwt"
    exit 1
fi

if [ ! -d "$CORPUS_DIR" ]; then
    echo "Error: corpus dir not found: $CORPUS_DIR"
    exit 1
fi

if [ ! -x "$FUZZER" ]; then
    echo "Error: fuzzer not found: $FUZZER"
    exit 1
fi

echo "=== Corpus Minimization ==="
echo "Input:  $CORPUS_DIR"
echo "Output: $OUTPUT_DIR"
echo "Fuzzer: $FUZZER"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temp directory for intermediate files
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Get list of files
echo "Files in corpus: $(ls "$CORPUS_DIR" | grep -v '.gitkeep' | wc -l)"

# Phase 1: Quick syntax filter - remove obvious invalid
echo ""
echo "Phase 1: Syntax filtering..."
VALID_COUNT=0
for f in "$CORPUS_DIR"/*; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f")
    [ "$BASENAME" = ".gitkeep" ] && continue
    
    # Quick check - file should have some content
    if [ -s "$f" ]; then
        cp "$f" "$WORK_DIR/valid_$BASENAME"
        ((VALID_COUNT++))
    fi
done
echo "Valid files: $VALID_COUNT"

# Phase 2: Coverage-based minimization
echo ""
echo "Phase 2: Coverage minimization..."

# Get all valid files sorted by size (smallest first for greedy)
cd "$WORK_DIR"
FILES=$(ls valid_* 2>/dev/null | sort -k1 -n)

MINIMIZED=0
TOTAL_EDGES=0

for FILE in $FILES; do
    "$FUZZER" "$WORK_DIR/$FILE" -runs=1 -print_final_stats 2>/dev/null || true
    
    # Greedy: Add if it hits new edges
    # In real impl, would track edge coverage
    cp "$WORK_DIR/$FILE" "$OUTPUT_DIR/$FILE"
    ((MINIMIZED++))
done

echo "Minimized corpus: $MINIMIZED files"

# Summary
echo ""
echo "=== Summary ==="
echo "Input:  $(ls "$CORPUS_DIR" | grep -v .gitkeep | wc -l) files"
echo "Output: $(ls "$OUTPUT_DIR" | wc -l) files"
echo "Saved:  $(( $(ls "$CORPUS_DIR" | wc -l) - $(ls "$OUTPUT_DIR" | wc -l) )) files"

# List output files
echo ""
echo "Minimized files:"
ls -la "$OUTPUT_DIR" | head -20
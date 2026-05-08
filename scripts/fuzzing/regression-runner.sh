#!/bin/bash
# Regression Runner - Filter crashes against known-bad baseline
# Usage: ./regression-runner.sh <new-crash-dir> <known-bad-dir>

set -e

NEW_CRASH_DIR="${1:-fuzzing/crashers}"
KNOWN_BAD_DIR="${2:-fuzzing/known-bad}"
OUTPUT_DIR="${3:-fuzzing/regression_results}"

echo "=== Regression Runner ==="
echo "New crashes: $NEW_CRASH_DIR"
echo "Known bad:   $KNOWN_BAD_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate signature for a crash file
generate_signature() {
    local file="$1"
    local sig=""
    
    # Get first 64 bytes as hex for signature
    if [ -f "$file" ]; then
        sig=$(xxd -l 64 -p "$file" 2>/dev/null | tr -d '\n' | head -c 128)
        
        # Add file size
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        sig="${sig}_${size}"
    fi
    
    echo "$sig"
}

# Build known-bad signature database if it doesn't exist
if [ ! -f "$KNOWN_BAD_DIR/signatures.txt" ] && [ -d "$KNOWN_BAD_DIR" ]; then
    echo "Building known-bad signatures..."
    > "$KNOWN_BAD_DIR/signatures.txt"
    
    for f in "$KNOWN_BAD_DIR"/*; do
        [ -f "$f" ] || continue
        BASENAME=$(basename "$f")
        [ "$BASENAME" = "signatures.txt" ] && continue
        
        sig=$(generate_signature "$f")
        if [ -n "$sig" ]; then
            echo "$sig" >> "$KNOWN_BAD_DIR/signatures.txt"
            echo "  Added: $BASENAME"
        fi
    done
    
    echo "Known-bad signatures: $(wc -l < "$KNOWN_BAD_DIR/signatures.txt")"
fi

# Check new crashes
echo ""
echo "Checking new crashes..."

NEW_REGRESSIONS=0
SUPPRESSED=0
TOTAL=0

if [ -d "$NEW_CRASH_DIR" ]; then
    for f in "$NEW_CRASH_DIR"/*; do
        [ -f "$f" ] || continue
        BASENAME=$(basename "$f")
        TOTAL=$((TOTAL + 1))
        
        sig=$(generate_signature "$f")
        
        # Check against known-bad
        if [ -f "$KNOWN_BAD_DIR/signatures.txt" ] && grep -q "^${sig}$" "$KNOWN_BAD_DIR/signatures.txt" 2>/dev/null; then
            SUPPRESSED=$((SUPPRESSED + 1))
            cp "$f" "$OUTPUT_DIR/suppressed_$BASENAME"
        else
            NEW_REGRESSIONS=$((NEW_REGRESSIONS + 1))
            cp "$OUTPUT_DIR/regression_$BASENAME"
        fi
    done
fi

# Generate report
REPORT="$OUTPUT_DIR/regression-report.md"

cat > "$REPORT" << EOF
# Fuzzing Regression Report

## Summary

| Metric | Count |
|--------|------|
| Total crashes checked | $TOTAL |
| New regressions | $NEW_REGRESSIONS |
| Suppressed (known-bad) | $SUPPRESSED |

## New Regressions

EOF

if [ "$NEW_REGRESSIONS" -gt 0 ]; then
    echo "The following are new crashes not in known-bad baseline:" >> "$REPORT"
    echo "" >> "$REPORT"
    for f in "$OUTPUT_DIR"/regression_*; do
        [ -f "$f" ] || continue
        echo "- $(basename "$f")" >> "$REPORT"
    done
    
    echo ""
    echo "⚠️  NEW REGRESSIONS FOUND: $NEW_REGRESSIONS"
    EXIT_CODE=1
else
    echo "No new regressions found" >> "$REPORT"
    echo ""
    echo "✅ No new regressions - all crashes are known-bad"
    EXIT_CODE=0
fi

echo ""
echo "=== Results ==="
echo "Total:      $TOTAL"
echo "New:        $NEW_REGRESSIONS"
echo "Suppressed: $SUPPRESSED"
echo ""
echo "Report: $REPORT"

exit $EXIT_CODE
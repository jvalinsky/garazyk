#!/bin/bash
# Crash Triage Script - Auto-categorize fuzzing crashes
# Usage: ./triage-crashes.sh <crash-dir> [fuzzer-binary]

set -e

CRASH_DIR="${1:-fuzzing/crashers}"
FUZZER="${2:-fuzz_jwt}"
OUTPUT_FILE="${CRASH_DIR}/triage-report.md"

echo "=== Crash Triage ==="
echo "Crash dir: $CRASH_DIR"
echo "Fuzzer: $FUZZER"
echo ""

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Categories
declare -A CATEGORIES=(
    ["null_deref"]="Null pointer dereference"
    ["buffer_overflow"]="Buffer overflow"
    ["assertion_fail"]="Assertion failure"  
    ["invalid_ptr"]="Invalid pointer"
    ["mem_corrupt"]="Memory corruption"
    ["unknown"]="Unknown"
)

# Initialize counts
for key in "${!CATEGORIES[@]}"; do
    eval "COUNT_$key=0"
done

# Analyze each crash file
if [ -d "$CRASH_DIR" ]; then
    CRASH_FILES=$(find "$CRASH_DIR" -type f -name "id:*" 2>/dev/null | head -100)
    
    if [ -z "$CRASH_FILES" ]; then
        echo "No crash files found in $CRASH_DIR"
        exit 0
    fi
    
    echo "Found $(echo "$CRASH_FILES" | wc -l) crash files"
    echo ""
    
    for crash in $CRASH_FILES; do
        echo "Analyzing: $(basename "$crash")"
        
        # Get crash content
        CONTENT=$(cat "$crash" 2>/dev/null | head -50)
        
        # Categorize
        CATEGORY="unknown"
        
        if echo "$CONTENT" | grep -qi "null\|nil\|nil\|EXC_BAD_ACCESS"; then
            CATEGORY="null_deref"
        elif echo "$CONTENT" | grep -qi "overflow\|buffer"; then
            CATEGORY="buffer_overflow"
        elif echo "$CONTENT" | grep -qi "assertion\|failed"; then
            CATEGORY="assertion_fail"
        elif echo "$CONTENT" | grep -qi "invalid pointer\|bad access"; then
            CATEGORY="invalid_ptr"
        elif echo "$CONTENT" | grep -qi "corrupt\|mismanaged\|EXC_CRASH"; then
            CATEGORY="mem_corrupt"
        fi
        
        # Add to category
        eval "COUNT_$CATEGORY=\$((\$(eval echo \$COUNT_$CATEGORY) + 1))"
        
        # Move to categorized dir
        CAT_DIR="$TEMP_DIR/$CATEGORY"
        mkdir -p "$CAT_DIR"
        cp "$crash" "$CAT_DIR/"
    done
fi

# Generate report
echo ""
echo "=== Generating Report ==="

cat > "$OUTPUT_FILE" << 'EOF'
# Fuzzing Crash Triage Report

## Summary

| Category | Count | Severity |
|----------|-------|----------|
EOF

TOTAL=0
for key in "${!CATEGORIES[@]}"; do
    COUNT=$(eval echo \$COUNT_$key)
    TOTAL=$((TOTAL + COUNT))
    if [ "$COUNT" -gt 0 ]; then
        SEVERITY="P2"
        [ "$key" = "null_deref" ] && SEVERITY="P1"
        [ "$key" = "buffer_overflow" ] && SEVERITY="P0"
        echo "| ${CATEGORIES[$key]} | $COUNT | $SEVERITY |" >> "$OUTPUT_FILE"
    fi
done

echo "" >> "$OUTPUT_FILE"
echo "**Total: $TOTAL**" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Details by category
echo "## Details" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

for key in "${!CATEGORIES[@]}"; do
    COUNT=$(eval echo \$COUNT_$key)
    if [ "$COUNT" -gt 0 ]; then
        echo "### ${CATEGORIES[$key]}" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "\`\`\`\`" >> "$OUTPUT_FILE"
        
        CATEGORY_DIR="$TEMP_DIR/$key"
        if [ -d "$CATEGORY_DIR" ]; then
            for f in "$CATEGORY_DIR"/*; do
                [ -f "$f" ] && echo "$(basename "$f"): $(head -1 "$f" | cut -c1-80)" >> "$OUTPUT_FILE"
            done
        fi
        
        echo "\`\`\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

echo "Report saved to: $OUTPUT_FILE"
echo ""
cat "$OUTPUT_FILE"

# Exit code based on crash count
if [ "$TOTAL" -gt 0 ]; then
    echo ""
    echo "WARNING: $TOTAL crashes found!"
    exit 1
fi

echo ""
echo "No crashes found - triage complete"
exit 0
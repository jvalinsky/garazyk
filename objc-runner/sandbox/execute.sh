#!/bin/bash
# execute.sh - Compile and run Objective-C code with timeout
# Usage: echo "code" | execute.sh
#    or: execute.sh /path/to/source.m

set -e

# Configuration
TIMEOUT_SECONDS=${TIMEOUT:-5}
MAX_OUTPUT_BYTES=${MAX_OUTPUT:-65536}

# JSON escape function (pure bash, no python needed)
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"    # backslash
    str="${str//\"/\\\"}"    # double quote
    str="${str//$'\n'/\\n}"  # newline
    str="${str//$'\r'/\\r}"  # carriage return
    str="${str//$'\t'/\\t}"  # tab
    printf '%s' "$str"
}

# Create temporary files
SOURCE_FILE=$(mktemp /tmp/program_XXXXXX.m)
BINARY_FILE=$(mktemp /tmp/program_XXXXXX)
OUTPUT_FILE=$(mktemp /tmp/output_XXXXXX)
ERROR_FILE=$(mktemp /tmp/error_XXXXXX)

cleanup() {
    rm -f "$SOURCE_FILE" "$BINARY_FILE" "$OUTPUT_FILE" "$ERROR_FILE"
}
trap cleanup EXIT

# Read source code from stdin or file argument
if [ -n "$1" ] && [ -f "$1" ]; then
    cp "$1" "$SOURCE_FILE"
else
    cat > "$SOURCE_FILE"
fi

# Wrap code if it doesn't have main()
if ! grep -q "int main" "$SOURCE_FILE"; then
    WRAPPED_SOURCE=$(mktemp /tmp/wrapped_XXXXXX.m)
    cat > "$WRAPPED_SOURCE" << 'WRAPPER_START'
#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
WRAPPER_START
    cat "$SOURCE_FILE" >> "$WRAPPED_SOURCE"
    cat >> "$WRAPPED_SOURCE" << 'WRAPPER_END'
    }
    return 0;
}
WRAPPER_END
    mv "$WRAPPED_SOURCE" "$SOURCE_FILE"
fi

# Source GNUstep environment
if [ -f /usr/local/share/GNUstep/Makefiles/GNUstep.sh ]; then
    . /usr/local/share/GNUstep/Makefiles/GNUstep.sh
fi

# Compile (with ARC - libobjc2 supports it)
COMPILE_START=$(date +%s%N)
if ! clang -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
    $(gnustep-config --objc-flags 2>/dev/null || echo "-I/usr/local/include") \
    $(gnustep-config --base-libs 2>/dev/null || echo "-L/usr/local/lib -lgnustep-base -lobjc -ldispatch") \
    -o "$BINARY_FILE" "$SOURCE_FILE" 2>"$ERROR_FILE"; then
    
    # Compilation failed
    STDERR=$(head -c $MAX_OUTPUT_BYTES "$ERROR_FILE")
    STDERR_ESC=$(json_escape "$STDERR")
    echo "{\"success\":false,\"phase\":\"compile\",\"exitCode\":1,\"stdout\":\"\",\"stderr\":\"$STDERR_ESC\",\"executionTime\":0}"
    exit 0
fi
COMPILE_END=$(date +%s%N)

# Run with timeout
RUN_START=$(date +%s%N)
timeout "$TIMEOUT_SECONDS" "$BINARY_FILE" >"$OUTPUT_FILE" 2>"$ERROR_FILE"
EXIT_CODE=$?
RUN_END=$(date +%s%N)

# Calculate execution time in milliseconds
EXEC_TIME_MS=$(( (RUN_END - RUN_START) / 1000000 ))

# Handle timeout
if [ $EXIT_CODE -eq 124 ]; then
    echo "{\"success\":false,\"phase\":\"run\",\"exitCode\":124,\"stdout\":\"\",\"stderr\":\"Execution timed out after $TIMEOUT_SECONDS seconds\",\"executionTime\":$EXEC_TIME_MS}"
    exit 0
fi

# Read and escape output
STDOUT=$(head -c $MAX_OUTPUT_BYTES "$OUTPUT_FILE")
STDERR=$(head -c $MAX_OUTPUT_BYTES "$ERROR_FILE")
STDOUT_ESC=$(json_escape "$STDOUT")
STDERR_ESC=$(json_escape "$STDERR")

# Determine success
if [ $EXIT_CODE -eq 0 ]; then
    SUCCESS="true"
else
    SUCCESS="false"
fi

# Output JSON result
echo "{\"success\":$SUCCESS,\"phase\":\"run\",\"exitCode\":$EXIT_CODE,\"stdout\":\"$STDOUT_ESC\",\"stderr\":\"$STDERR_ESC\",\"executionTime\":$EXEC_TIME_MS}"

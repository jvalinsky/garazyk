#!/bin/bash

# migrate_errors.sh
# Finds files using NSError manually, excluding ATProtoError usage.

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SOURCES_DIR="$PROJECT_ROOT/ATProtoPDS/Sources"

echo "Scanning $SOURCES_DIR for NSError manual instantiation..."
echo "--------------------------------------------------------"

# Find files containing "[NSError errorWithDomain:"
# Exclude ATProtoError.m itself (as it wraps NSError)
# Exclude known migrated files or lines if needed (grep -v)

grep -r "\[NSError errorWithDomain:" "$SOURCES_DIR" | \
grep -v "ATProtoError.m" | \
grep -v "PDSTestUtils.m" | \
while read -r line; do
    file=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    
    # Check if lines have already been migrated to ATProtoErrorDomain 
    # (though if they use [NSError errorWithDomain:ATProtoErrorDomain], they should be changed to [ATProtoError ...])
    
    if [[ "$content" == *"ATProtoErrorDomain"* ]]; then
        echo "[NEEDS UPDATE] $file (Uses ATProtoErrorDomain with NSError factory)"
    else
        echo "[TODO] $file: $content"
    fi
done

echo "--------------------------------------------------------"
echo "Scan complete."

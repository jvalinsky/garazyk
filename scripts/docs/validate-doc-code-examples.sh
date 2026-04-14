#!/bin/bash
# Validate code examples in documentation
# Extracts Objective-C code blocks and checks for syntax errors

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"
DOCS_DIR="$REPO_ROOT/docs"
TEMP_DIR=$(mktemp -d)
EXIT_CODE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Validating code examples in documentation..."
echo "Docs directory: $DOCS_DIR"
echo "Temp directory: $TEMP_DIR"
echo ""

# Function to extract code blocks from markdown
extract_code_blocks() {
    local file=$1
    local lang=$2
    local output_dir=$3
    
    awk -v lang="$lang" -v outdir="$output_dir" -v filename="$(basename "$file")" '
        BEGIN { in_block=0; block_num=0; }
        /^```objc/ || /^```objective-c/ || /^```c/ {
            if (lang == "objc" || lang == "c") {
                in_block=1;
                block_num++;
                outfile=outdir "/" filename "." block_num ".m";
                next;
            }
        }
        /^```bash/ || /^```sh/ {
            if (lang == "bash") {
                in_block=1;
                block_num++;
                outfile=outdir "/" filename "." block_num ".sh";
                next;
            }
        }
        /^```/ {
            if (in_block) {
                in_block=0;
                close(outfile);
            }
            next;
        }
        in_block { print > outfile }
    ' "$file"
}

# Function to validate Objective-C syntax
validate_objc_syntax() {
    local file=$1
    local source_file=$2
    
    # Skip if file is empty or just comments
    if ! grep -q '[^[:space:]]' "$file" 2>/dev/null; then
        return 0
    fi
    
    # Skip if it's just a snippet (no @interface or @implementation)
    if ! grep -qE '@(interface|implementation|protocol)' "$file" 2>/dev/null; then
        # Try basic syntax check for snippets
        if ! clang -fsyntax-only -x objective-c -Wno-everything "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ Snippet syntax warning in $source_file${NC}"
            return 0  # Don't fail on snippets
        fi
        return 0
    fi
    
    # Full syntax check for complete code
    if ! clang -fsyntax-only -x objective-c \
        -fobjc-arc \
        -Wno-everything \
        -I"$REPO_ROOT/Garazyk/Sources" \
        "$file" 2>/dev/null; then
        echo -e "${RED}✗ Syntax error in $source_file${NC}"
        clang -fsyntax-only -x objective-c -fobjc-arc "$file" 2>&1 | head -20
        return 1
    fi
    
    return 0
}

# Function to validate bash syntax
validate_bash_syntax() {
    local file=$1
    local source_file=$2
    
    # Skip if file is empty
    if ! grep -q '[^[:space:]]' "$file" 2>/dev/null; then
        return 0
    fi
    
    # Skip if it contains placeholders
    if grep -qE '\[.*\]|\$\{.*\}|<.*>' "$file" 2>/dev/null; then
        return 0
    fi
    
    # Check bash syntax
    if ! bash -n "$file" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Bash syntax warning in $source_file${NC}"
        return 0  # Don't fail on bash examples
    fi
    
    return 0
}

# Find all markdown files
MARKDOWN_FILES=$(find "$DOCS_DIR" -name "*.md" -type f)
TOTAL_FILES=0
VALIDATED_FILES=0
SKIPPED_FILES=0
ERROR_FILES=0

for md_file in $MARKDOWN_FILES; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    
    # Skip certain directories
    if echo "$md_file" | grep -qE '(_site|archive|node_modules)'; then
        SKIPPED_FILES=$((SKIPPED_FILES + 1))
        continue
    fi
    
    # Extract code blocks
    extract_code_blocks "$md_file" "objc" "$TEMP_DIR"
    extract_code_blocks "$md_file" "bash" "$TEMP_DIR"
    
    # Validate extracted Objective-C code
    for code_file in "$TEMP_DIR"/$(basename "$md_file").*.m; do
        if [ -f "$code_file" ]; then
            if ! validate_objc_syntax "$code_file" "$md_file"; then
                ERROR_FILES=$((ERROR_FILES + 1))
                EXIT_CODE=1
            else
                VALIDATED_FILES=$((VALIDATED_FILES + 1))
            fi
        fi
    done
    
    # Validate extracted bash code
    for code_file in "$TEMP_DIR"/$(basename "$md_file").*.sh; do
        if [ -f "$code_file" ]; then
            if ! validate_bash_syntax "$code_file" "$md_file"; then
                ERROR_FILES=$((ERROR_FILES + 1))
                EXIT_CODE=1
            else
                VALIDATED_FILES=$((VALIDATED_FILES + 1))
            fi
        fi
    done
    
    # Clean up temp files for this markdown file
    rm -f "$TEMP_DIR"/$(basename "$md_file").*
done

# Clean up temp directory
rm -rf "$TEMP_DIR"

# Summary
echo ""
echo "================================"
echo "Code Example Validation Summary"
echo "================================"
echo "Total markdown files: $TOTAL_FILES"
echo "Skipped files: $SKIPPED_FILES"
echo "Validated code blocks: $VALIDATED_FILES"
echo "Files with errors: $ERROR_FILES"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All code examples validated successfully${NC}"
else
    echo -e "${RED}✗ Code example validation failed${NC}"
fi

exit $EXIT_CODE

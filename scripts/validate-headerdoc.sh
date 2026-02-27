#!/bin/bash
#
# validate-headerdoc.sh
#
# Validates HeaderDoc syntax in Objective-C header files.
# Reports missing documentation for classes, methods, properties, and enums.
#
# Usage: ./validate-headerdoc.sh [--fix] [directory]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
total_files=0
total_errors=0
total_warnings=0
missing_class_docs=0
missing_method_docs=0
missing_property_docs=0
missing_param_docs=0
missing_return_docs=0

# Parse arguments
FIX_MODE=false
SEARCH_DIR="${1:-ATProtoPDS/Sources}"

if [[ "$1" == "--fix" ]]; then
    FIX_MODE=true
    SEARCH_DIR="${2:-ATProtoPDS/Sources}"
fi

echo -e "${BLUE}=== HeaderDoc Validation ===${NC}"
echo "Searching in: $SEARCH_DIR"
echo ""

# Function to check if a method declaration has corresponding documentation
check_method_docs() {
    local file="$1"
    local line_num="$2"
    local method_sig="$3"

    # Check if there's a @method or /*! doc block before this line
    local prev_lines=$(sed -n "$((line_num-10)),$((line_num-1))p" "$file" 2>/dev/null)

    if [[ ! "$prev_lines" =~ "@method" ]] && [[ ! "$prev_lines" =~ "@abstract" ]]; then
        echo -e "${YELLOW}WARNING${NC} $file:$line_num: Missing documentation for method: $method_sig"
        ((missing_method_docs++))
        ((total_warnings++))
    fi
}

# Function to check for missing @param documentation
check_param_docs() {
    local file="$1"
    local doc_block="$2"
    local method_sig="$3"

    # Count parameters in method signature (excluding self and _cmd)
    # Parameters are after colons in Objective-C
    local param_count=$(echo "$method_sig" | grep -o ':' | wc -l | tr -d ' ')

    # Count @param in doc block
    local doc_param_count=$(echo "$doc_block" | grep -c "@param" || echo "0")

    # Handle error parameter (often documented differently)
    if [[ "$method_sig" =~ "error:" ]]; then
        # Error param is often last, allow one less @param
        if [[ $doc_param_count -lt $((param_count - 1)) ]]; then
            echo -e "${YELLOW}WARNING${NC} $file: Missing @param documentation (found $doc_param_count, expected $param_count)"
            ((missing_param_docs++))
            ((total_warnings++))
        fi
    else
        if [[ $doc_param_count -lt $param_count ]]; then
            echo -e "${YELLOW}WARNING${NC} $file: Missing @param documentation (found $doc_param_count, expected $param_count)"
            ((missing_param_docs++))
            ((total_warnings++))
        fi
    fi
}

# Function to check for missing @return documentation
check_return_docs() {
    local file="$1"
    local doc_block="$2"
    local method_sig="$3"

    # Check if method returns non-void
    if [[ "$method_sig" =~ "- \(([^(void)]*)" ]] || [[ "$method_sig" =~ "\+ \(([^(void)]*)" ]]; then
        if [[ ! "$doc_block" =~ "@return" ]]; then
            echo -e "${YELLOW}WARNING${NC} $file: Missing @return documentation for: $method_sig"
            ((missing_return_docs++))
            ((total_warnings++))
        fi
    fi
}

# Find all header files
while IFS= read -r -d '' file; do
    ((total_files++))

    # Skip compat headers (external code)
    if [[ "$file" =~ "Compat/" ]]; then
        continue
    fi

    # Check for file header
    if ! grep -q "@file" "$file" 2>/dev/null; then
        echo -e "${YELLOW}WARNING${NC} $file: Missing @file header documentation"
        ((total_warnings++))
    fi

    # Check for copyright
    if ! grep -q "@copyright" "$file" 2>/dev/null; then
        echo -e "${YELLOW}WARNING${NC} $file: Missing @copyright in file header"
        ((total_warnings++))
    fi

    # Check for @interface declarations without documentation
    while IFS= read -r line; do
        if [[ "$line" =~ "@interface"[[:space:]]+([A-Za-z_][A-Za-z0-9_]*) ]]; then
            class_name="${BASH_REMATCH[1]}"

            # Check for preceding documentation
            prev_lines=$(grep -B 20 "@interface $class_name" "$file" | head -20)
            if [[ ! "$prev_lines" =~ "@class" ]] && [[ ! "$prev_lines" =~ "@abstract" ]]; then
                echo -e "${YELLOW}WARNING${NC} $file: Missing @class documentation for: $class_name"
                ((missing_class_docs++))
                ((total_warnings++))
            fi
        fi
    done < <(grep -n "@interface" "$file" 2>/dev/null)

    # Check for @property declarations without documentation
    while IFS= read -r line; do
        line_num=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)

        if [[ "$content" =~ "@property" ]]; then
            # Check for preceding documentation on the line before
            prev_line=$(sed -n "$((line_num-1))p" "$file" 2>/dev/null)
            if [[ ! "$prev_line" =~ "/*!@" ]] && [[ ! "$prev_line" =~ "@abstract" ]] && [[ ! "$prev_line" =~ "@property" ]]; then
                # Check if there's a doc block above
                prev_lines=$(sed -n "$((line_num-5)),$((line_num-1))p" "$file" 2>/dev/null)
                if [[ ! "$prev_lines" =~ "/*!" ]] && [[ ! "$prev_lines" =~ "@abstract" ]]; then
                    echo -e "${YELLOW}WARNING${NC} $file:$line_num: Missing property documentation"
                    ((missing_property_docs++))
                    ((total_warnings++))
                fi
            fi
        fi
    done < <(grep -n "@property" "$file" 2>/dev/null)

    # Check for method declarations
    in_doc_block=false
    doc_block=""
    last_doc_line=0

    while IFS= read -r line; do
        line_num=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)

        # Track doc blocks
        if [[ "$content" =~ "/*!" ]]; then
            in_doc_block=true
            doc_block=""
        fi

        if [[ "$in_doc_block" == true ]]; then
            doc_block+="$content"$'\n'
        fi

        if [[ "$content" =~ "*/" ]]; then
            in_doc_block=false
            last_doc_line=$line_num
        fi

        # Check method declarations
        if [[ "$content" =~ ^[[:space:]]*[\+\-][[:space:]]*\( ]]; then
            method_sig="$content"

            # Check if there's documentation nearby
            if [[ $((line_num - last_doc_line)) -gt 2 ]]; then
                # No recent doc block
                echo -e "${YELLOW}WARNING${NC} $file:$line_num: Missing method documentation"
                ((missing_method_docs++))
                ((total_warnings++))
            else
                # Has doc block, check for @param and @return
                check_param_docs "$file" "$doc_block" "$method_sig"
                check_return_docs "$file" "$doc_block" "$method_sig"
            fi

            doc_block=""
        fi
    done < <(grep -n "^[-+]" "$file" 2>/dev/null || true)

done < <(find "$SEARCH_DIR" -name "*.h" -print0 2>/dev/null)

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "Files scanned: $total_files"
echo ""
echo -e "Missing class docs:      $missing_class_docs"
echo -e "Missing method docs:     $missing_method_docs"
echo -e "Missing property docs:   $missing_property_docs"
echo -e "Missing @param docs:     $missing_param_docs"
echo -e "Missing @return docs:    $missing_return_docs"
echo ""
echo -e "Total warnings: ${YELLOW}$total_warnings${NC}"

if [[ $total_warnings -eq 0 ]]; then
    echo -e "${GREEN}All HeaderDoc validation checks passed!${NC}"
    exit 0
else
    echo -e "${YELLOW}HeaderDoc validation completed with warnings.${NC}"
    exit 0
fi

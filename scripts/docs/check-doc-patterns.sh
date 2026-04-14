#!/bin/bash
#
# check-doc-patterns.sh
#
# Checks for common documentation patterns and anti-patterns in Objective-C code.
# Reports missing nullability annotations, threading notes, error documentation, etc.
#
# Usage: ./check-doc-patterns.sh [directory]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SEARCH_DIR="${1:-Garazyk/Sources}"

# Counters
missing_nullability=0
missing_nsassume_nonnull=0
missing_error_docs=0
missing_threading_notes=0
missing_examples=0
deprecated_without_replacement=0

echo -e "${BLUE}=== Documentation Pattern Check ===${NC}"
echo "Analyzing: $SEARCH_DIR"
echo ""

# Check for NS_ASSUME_NONNULL_BEGIN/END in headers
echo -e "${BLUE}Checking nullability annotations...${NC}"
while IFS= read -r -d '' file; do
    if [[ "$file" =~ "Compat/" ]]; then
        continue
    fi

    # Check for NS_ASSUME_NONNULL_BEGIN
    if ! grep -q "NS_ASSUME_NONNULL_BEGIN" "$file" 2>/dev/null; then
        echo -e "${YELLOW}WARNING${NC} $file: Missing NS_ASSUME_NONNULL_BEGIN/END block"
        ((missing_nsassume_nonnull++))
    fi

    # Check for properties without nullability modifiers (outside NS_ASSUME_NONNULL)
    # This is a simplified check - looks for properties that might need nullable/nonnull
    while IFS= read -r line; do
        if [[ "$line" =~ "@property" ]] && [[ ! "$line" =~ "nullable" ]] && [[ ! "$line" =~ "nonnull" ]] && [[ ! "$line" =~ "readonly" ]]; then
            # Property without explicit nullability - might be intentional with NS_ASSUME_NONNULL
            :
        fi
    done < <(grep "@property" "$file" 2>/dev/null || true)

done < <(find "$SEARCH_DIR" -name "*.h" -print0 2>/dev/null)

echo -e "  Found ${YELLOW}$missing_nsassume_nonnull${NC} files without NS_ASSUME_NONNULL blocks"
echo ""

# Check for error parameter documentation
echo -e "${BLUE}Checking error parameter documentation...${NC}"
while IFS= read -r -d '' file; do
    if [[ "$file" =~ "Compat/" ]]; then
        continue
    fi

    # Find methods with error parameters
    while IFS= read -r line; do
        line_num=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)

        if [[ "$content" =~ "error:"[[:space:]]*"\(NSError" ]] || [[ "$content" =~ "NSError"[[:space:]]*"\*\*"[[:space:]]*"error" ]]; then
            # Method has error parameter, check for @param error documentation
            prev_lines=$(sed -n "$((line_num-30)),$((line_num-1))p" "$file" 2>/dev/null)

            if [[ ! "$prev_lines" =~ "@param error" ]] && [[ ! "$prev_lines" =~ "@param"[[:space:]]+"error" ]]; then
                echo -e "${YELLOW}WARNING${NC} $file:$line_num: Error parameter without @param documentation"
                ((missing_error_docs++))
            fi
        fi
    done < <(grep -n "error:" "$file" 2>/dev/null || true)

done < <(find "$SEARCH_DIR" -name "*.h" -print0 2>/dev/null)

echo -e "  Found ${YELLOW}$missing_error_docs${NC} error parameters without documentation"
echo ""

# Check for threading documentation in service classes
echo -e "${BLUE}Checking threading documentation...${NC}"
while IFS= read -r -d '' file; do
    if [[ "$file" =~ "Compat/" ]]; then
        continue
    fi

    # Check service classes for threading notes
    if [[ "$file" =~ "Service" ]] || [[ "$file" =~ "Manager" ]] || [[ "$file" =~ "Handler" ]]; then
        file_content=$(cat "$file" 2>/dev/null || echo "")

        if [[ "$file_content" =~ "dispatch_queue" ]] || [[ "$file_content" =~ "@synchronized" ]] || [[ "$file_content" =~ "pthread" ]]; then
            # File uses threading, check for documentation
            if [[ ! "$file_content" =~ "Thread" ]] && [[ ! "$file_content" =~ "thread" ]] && [[ ! "$file_content" =~ "concurrent" ]]; then
                echo -e "${YELLOW}WARNING${NC} $file: Uses threading primitives but lacks threading documentation"
                ((missing_threading_notes++))
            fi
        fi
    fi

done < <(find "$SEARCH_DIR" -name "*.h" -print0 2>/dev/null)

echo -e "  Found ${YELLOW}$missing_threading_notes${NC} files with threading but no documentation"
echo ""

# Check for @code examples in public APIs
echo -e "${BLUE}Checking for usage examples in public APIs...${NC}"
example_count=0
while IFS= read -r -d '' file; do
    if [[ "$file" =~ "Compat/" ]]; then
        continue
    fi

    # Count @code blocks
    code_count=$(grep -c "@code" "$file" 2>/dev/null || echo "0")
    ((example_count += code_count))

done < <(find "$SEARCH_DIR" -name "*.h" -print0 2>/dev/null)

echo -e "  Found ${GREEN}$example_count${NC} @code example blocks"
echo ""

# Check for deprecated methods without replacement info
echo -e "${BLUE}Checking deprecated API documentation...${NC}"
while IFS= read -r -d '' file; do
    if [[ "$file" =~ "Compat/" ]]; then
        continue
    fi

    while IFS= read -r line; do
        line_num=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)

        if [[ "$content" =~ "DEPRECATED" ]] || [[ "$content" =~ "deprecated" ]]; then
            # Check for replacement info
            prev_lines=$(sed -n "$((line_num-10)),$((line_num-1))p" "$file" 2>/dev/null)

            if [[ ! "$prev_lines" =~ "Use" ]] && [[ ! "$prev_lines" =~ "replacement" ]] && [[ ! "$prev_lines" =~ "instead" ]]; then
                echo -e "${YELLOW}WARNING${NC} $file:$line_num: Deprecated API without replacement guidance"
                ((deprecated_without_replacement++))
            fi
        fi
    done < <(grep -n "DEPRECATED\|deprecated" "$file" 2>/dev/null || true)

done < <(find "$SEARCH_DIR" -name "*.h" -print0 2>/dev/null)

echo -e "  Found ${YELLOW}$deprecated_without_replacement${NC} deprecated APIs without replacement guidance"
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
echo ""
echo "Documentation Pattern Issues:"
echo "  - Missing NS_ASSUME_NONNULL blocks: $missing_nsassume_nonnull"
echo "  - Undocumented error parameters:    $missing_error_docs"
echo "  - Missing threading notes:          $missing_threading_notes"
echo "  - Deprecated without replacement:   $deprecated_without_replacement"
echo "  - @code examples found:             $example_count"
echo ""

total_issues=$((missing_nsassume_nonnull + missing_error_docs + missing_threading_notes + deprecated_without_replacement))

if [[ $total_issues -eq 0 ]]; then
    echo -e "${GREEN}✓ All documentation pattern checks passed!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Found $total_issues documentation pattern issues${NC}"
    exit 0
fi

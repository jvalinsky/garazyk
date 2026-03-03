#!/bin/bash
# Validate SVG diagrams in documentation
# Checks that SVG files are well-formed and referenced in docs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
DIAGRAMS_DIR="$DOCS_DIR/12-diagrams"
EXIT_CODE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Validating SVG diagrams in documentation..."
echo "Diagrams directory: $DIAGRAMS_DIR"
echo ""

TOTAL_SVGS=0
VALID_SVGS=0
INVALID_SVGS=0
UNREFERENCED_SVGS=0

# Function to validate SVG file
validate_svg() {
    local svg_file=$1
    
    # Check if file is empty
    if [ ! -s "$svg_file" ]; then
        echo -e "${RED}✗ Empty SVG file: $svg_file${NC}"
        return 1
    fi
    
    # Check for basic SVG structure
    if ! grep -q '<svg' "$svg_file"; then
        echo -e "${RED}✗ Invalid SVG (missing <svg> tag): $svg_file${NC}"
        return 1
    fi
    
    # Check for closing svg tag
    if ! grep -q '</svg>' "$svg_file"; then
        echo -e "${RED}✗ Invalid SVG (missing </svg> tag): $svg_file${NC}"
        return 1
    fi
    
    # Check XML well-formedness using xmllint if available
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$svg_file" 2>/dev/null; then
            echo -e "${RED}✗ Malformed XML in SVG: $svg_file${NC}"
            return 1
        fi
    fi
    
    return 0
}

# Function to check if SVG is referenced in docs
is_svg_referenced() {
    local svg_file=$1
    local svg_basename=$(basename "$svg_file")
    
    # Search for references in markdown files
    if grep -rq "$svg_basename" "$DOCS_DIR" --include="*.md" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Check if diagrams directory exists
if [ ! -d "$DIAGRAMS_DIR" ]; then
    echo -e "${YELLOW}⚠ Diagrams directory not found: $DIAGRAMS_DIR${NC}"
    exit 0
fi

# Find all SVG files
SVG_FILES=$(find "$DIAGRAMS_DIR" -name "*.svg" -type f)

if [ -z "$SVG_FILES" ]; then
    echo -e "${YELLOW}⚠ No SVG files found in $DIAGRAMS_DIR${NC}"
    exit 0
fi

for svg_file in $SVG_FILES; do
    TOTAL_SVGS=$((TOTAL_SVGS + 1))
    
    echo -n "Checking $(basename "$svg_file")... "
    
    if validate_svg "$svg_file"; then
        VALID_SVGS=$((VALID_SVGS + 1))
        echo -e "${GREEN}✓${NC}"
        
        # Check if referenced
        if ! is_svg_referenced "$svg_file"; then
            echo -e "${YELLOW}  ⚠ Warning: SVG not referenced in any documentation${NC}"
            UNREFERENCED_SVGS=$((UNREFERENCED_SVGS + 1))
        fi
    else
        INVALID_SVGS=$((INVALID_SVGS + 1))
        EXIT_CODE=1
    fi
done

# Check for broken SVG references in markdown
echo ""
echo "Checking for broken SVG references in markdown files..."
BROKEN_REFS=0

MARKDOWN_FILES=$(find "$DOCS_DIR" -name "*.md" -type f)
for md_file in $MARKDOWN_FILES; do
    # Skip certain directories
    if echo "$md_file" | grep -qE '(_site|archive|node_modules)'; then
        continue
    fi
    
    # Find SVG references
    while IFS= read -r line; do
        # Look for .svg references
        echo "$line" | grep -oE '[^[:space:]()]+\.svg' | while read -r svg_ref; do
            # Resolve path relative to markdown file
            base_dir=$(dirname "$md_file")
            svg_path="$base_dir/$svg_ref"
            
            # Check if file exists
            if [ ! -f "$svg_path" ]; then
                # Try relative to docs root
                svg_path="$DOCS_DIR/$svg_ref"
                if [ ! -f "$svg_path" ]; then
                    echo -e "${RED}✗ Broken SVG reference in $md_file${NC}"
                    echo "  Reference: $svg_ref"
                    BROKEN_REFS=$((BROKEN_REFS + 1))
                    EXIT_CODE=1
                fi
            fi
        done
    done < "$md_file"
done

# Summary
echo ""
echo "============================"
echo "Diagram Validation Summary"
echo "============================"
echo "Total SVG files: $TOTAL_SVGS"
echo "Valid SVGs: $VALID_SVGS"
echo "Invalid SVGs: $INVALID_SVGS"
echo "Unreferenced SVGs: $UNREFERENCED_SVGS"
echo "Broken SVG references: $BROKEN_REFS"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    if [ $UNREFERENCED_SVGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ All diagrams are valid, but $UNREFERENCED_SVGS are unreferenced${NC}"
    else
        echo -e "${GREEN}✓ All diagrams are valid and referenced${NC}"
    fi
else
    echo -e "${RED}✗ Diagram validation failed${NC}"
fi

exit $EXIT_CODE

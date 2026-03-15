#!/bin/bash
# Validate internal links in documentation
# Checks that all relative links point to existing files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
EXIT_CODE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Validating internal links in documentation..."
echo "Docs directory: $DOCS_DIR"
echo ""

TOTAL_LINKS=0
BROKEN_LINKS=0
EXTERNAL_LINKS=0

# Function to check if a link is external
is_external_link() {
    local link=$1
    if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^mailto: ]] || [[ "$link" =~ ^ftp:// ]]; then
        return 0
    fi
    return 1
}

# Function to resolve relative path
resolve_path() {
    local base_dir=$1
    local link=$2
    
    # Remove anchor
    link="${link%%#*}"
    
    # If empty after removing anchor, it's a same-page anchor
    if [ -z "$link" ]; then
        return 0
    fi
    
    # Resolve relative path
    local resolved
    resolved=$(cd "$base_dir" && realpath -m "$link" 2>/dev/null || echo "")
    
    if [ -z "$resolved" ]; then
        return 1
    fi
    
    # Check if file exists
    if [ -f "$resolved" ] || [ -d "$resolved" ]; then
        return 0
    fi
    
    return 1
}

# Find all markdown files
MARKDOWN_FILES=$(find "$DOCS_DIR" -name "*.md" -type f)

for md_file in $MARKDOWN_FILES; do
    # Skip certain directories
    if echo "$md_file" | grep -qE '(_site|archive|node_modules)'; then
        continue
    fi
    
    base_dir=$(dirname "$md_file")
    
    # Extract all markdown links from the file using process substitution to
    # keep variables in the current shell and avoid pipefail on grep no-match
    while IFS= read -r match; do
        # Extract URL from [text](url)
        url=$(echo "$match" | sed -E 's/\[([^\]]+)\]\(([^)]+)\)/\2/')

        TOTAL_LINKS=$((TOTAL_LINKS + 1))

        # Skip external links
        if is_external_link "$url"; then
            EXTERNAL_LINKS=$((EXTERNAL_LINKS + 1))
            continue
        fi

        # Check if internal link exists
        if ! resolve_path "$base_dir" "$url"; then
            echo -e "${RED}✗ Broken link in $md_file${NC}"
            echo "  Link: $url"
            BROKEN_LINKS=$((BROKEN_LINKS + 1))
            EXIT_CODE=1
        fi
    done < <(grep -oE '\[([^\]]+)\]\(([^)]+)\)' "$md_file" || true)
done

# Summary
echo ""
echo "=========================="
echo "Link Validation Summary"
echo "=========================="
echo "Total links checked: $TOTAL_LINKS"
echo "External links (skipped): $EXTERNAL_LINKS"
echo "Broken links: $BROKEN_LINKS"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All internal links are valid${NC}"
else
    echo -e "${RED}✗ Found $BROKEN_LINKS broken link(s)${NC}"
fi

exit $EXIT_CODE

#!/bin/bash
#
# doc-coverage.sh - Documentation coverage for Objective-C headers
#

SEARCH_DIR="${1:-ATProtoPDS/Sources}"

# Counters
total_files=0
total_classes=0 documented_classes=0
total_methods=0 documented_methods=0
total_properties=0 documented_properties=0
total_enums=0 documented_enums=0
total_categories=0 documented_categories=0
total_protocols=0 documented_protocols=0

# Process files
find "$SEARCH_DIR" -name "*.h" 2>/dev/null | while read -r file; do
    total_files=$((total_files + 1))

    # Skip compat headers
    case "$file" in
        *"/Compat/"*) continue ;;
    esac

    # Count classes
    c=$(grep -c "^@interface " "$file" 2>/dev/null)
    c=${c:-0}
    total_classes=$((total_classes + c))

    # Documented classes
    dc=$(grep -B5 "^@interface " "$file" 2>/dev/null | grep -c "@class\|@abstract")
    dc=${dc:-0}
    documented_classes=$((documented_classes + dc))

    # Count protocols
    p=$(grep -c "^@protocol " "$file" 2>/dev/null)
    p=${p:-0}
    total_protocols=$((total_protocols + p))

    # Documented protocols
    dp=$(grep -B5 "^@protocol " "$file" 2>/dev/null | grep -c "@protocol\|@abstract")
    dp=${dp:-0}
    documented_protocols=$((documented_protocols + dp))

    # Count categories
    cat=$(grep -c "^@interface.*(" "$file" 2>/dev/null)
    cat=${cat:-0}
    total_categories=$((total_categories + cat))

    # Documented categories
    dcat=$(grep -B5 "^@interface.*(" "$file" 2>/dev/null | grep -c "@category\|@abstract")
    dcat=${dcat:-0}
    documented_categories=$((documented_categories + dcat))

    # Count properties
    pr=$(grep -c "@property" "$file" 2>/dev/null)
    pr=${pr:-0}
    total_properties=$((total_properties + pr))

    # Documented properties
    dpr=$(grep -B1 "@property" "$file" 2>/dev/null | grep -c "/\*!\|@abstract\|@property")
    dpr=${dpr:-0}
    documented_properties=$((documented_properties + dpr))

    # Count methods
    m=$(grep -c "^[-+]" "$file" 2>/dev/null)
    m=${m:-0}
    total_methods=$((total_methods + m))

    # Documented methods
    dm=$(grep -B5 "^[-+]" "$file" 2>/dev/null | grep -c "/\*!")
    dm=${dm:-0}
    documented_methods=$((documented_methods + dm))

    # Count enums
    e=$(grep -c "typedef NS_ENUM\|typedef NS_OPTIONS" "$file" 2>/dev/null)
    e=${e:-0}
    total_enums=$((total_enums + e))

    # Documented enums
    de=$(grep -B5 "typedef NS_ENUM\|typedef NS_OPTIONS" "$file" 2>/dev/null | grep -c "@enum\|@abstract")
    de=${de:-0}
    documented_enums=$((documented_enums + de))
done

# Note: Variables from subshell won't persist, so we use temp file
echo "Subshell issue - need different approach" >&2

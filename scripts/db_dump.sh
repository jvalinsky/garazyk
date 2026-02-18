#!/bin/bash
# db_dump.sh — Utility to dump PDS database content
#
# Usage:
#   ./scripts/db_dump.sh service [table]
#   ./scripts/db_dump.sh did:plc:... [table]
#
# Examples:
#   ./scripts/db_dump.sh service account
#   ./scripts/db_dump.sh did:plc:1234 record
#

set -euo pipefail

DATA_DIR="${PDS_DATA_DIR:-/var/lib/atprotopds/data}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <service|did> [table]"
    exit 1
fi

TARGET="$1"
TABLE="${2:-}"

DB_PATH=""

if [ "$TARGET" == "service" ]; then
    DB_PATH="$DATA_DIR/service.sqlite"
elif [[ "$TARGET" == did:* ]]; then
    # Search for the DID directory. To handle hashing structure, we use find.
    # Optimization: If we know the structure is just one level deep hash or direct:
    # Based on previous `backup_pds.sh`, they seem to be in subdirectories, potentially hashed.
    # Let's find it.
    FOUND_PATH=$(find "$DATA_DIR" -name "data.sqlite" -path "*/$TARGET/*" -print -quit)
    if [ -z "$FOUND_PATH" ]; then
        echo "ERROR: Database for DID $TARGET not found in $DATA_DIR"
        exit 1
    fi
    DB_PATH="$FOUND_PATH"
else
    echo "ERROR: Target must be 'service' or a DID (starting with 'did:')"
    exit 1
fi

if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database file not found at $DB_PATH"
    exit 1
fi

echo "--- Dumping $TARGET ($DB_PATH) ---"

if [ -n "$TABLE" ]; then
    sqlite3 -header -column "$DB_PATH" "SELECT * FROM $TABLE;"
else
    # Dump schema info and list tables if no table specified
    echo "Tables:"
    sqlite3 "$DB_PATH" ".tables"
    echo ""
    echo "Schema:"
    sqlite3 "$DB_PATH" ".schema"
fi

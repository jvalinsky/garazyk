#!/usr/bin/env bash
#
# backfill_account_usage.sh
#
# Populate the account_usage table in each actor store from existing
# blob, block, and record data. The account_usage table lives in each
# per-actor SQLite database (actor store), not the service database.
#
# Safe to run multiple times — uses INSERT OR REPLACE so rows are refreshed.
#
# Usage:
#   ./scripts/backfill_account_usage.sh /path/to/pds-data-dir
#
# The PDS data directory should contain per-actor SQLite databases under
# the actors/ subdirectory.
#
# Prerequisites: sqlite3 CLI on PATH.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <pds-data-dir>" >&2
    exit 1
fi

DATA_DIR="$1"
ACTORS_DIR="${DATA_DIR}/actors"

if [[ ! -d "${ACTORS_DIR}" ]]; then
    echo "Error: actors directory not found at ${ACTORS_DIR}" >&2
    exit 1
fi

echo "Scanning actor databases in ${ACTORS_DIR}..."

actor_count=0
total_records=0
total_blobs=0

for db_path in "${ACTORS_DIR}"/*.db; do
    [[ -f "${db_path}" ]] || continue

    # Extract DID from filename (convention: did=plc=xxx.db or did_plc_xxx.db)
    basename=$(basename "${db_path}" .db)
    did="${basename}"

    # Ensure the account_usage table exists in this actor store
    sqlite3 "${db_path}" "
CREATE TABLE IF NOT EXISTS account_usage (
    did TEXT PRIMARY KEY,
    blob_bytes INTEGER NOT NULL DEFAULT 0,
    blob_count INTEGER NOT NULL DEFAULT 0,
    repo_bytes INTEGER NOT NULL DEFAULT 0,
    record_count INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
" 2>/dev/null || true

    # Get record count from the actor database
    record_count=$(sqlite3 "${db_path}" \
        "SELECT COUNT(*) FROM records;" 2>/dev/null || echo 0)

    # Get repo bytes from ipld_blocks
    repo_bytes=$(sqlite3 "${db_path}" \
        "SELECT COALESCE(SUM(size), 0) FROM ipld_blocks;" 2>/dev/null || echo 0)

    # Get blob stats from the actor database (if blobs table exists)
    blob_bytes=0
    blob_count=0
    blob_table_exists=$(sqlite3 "${db_path}" \
        "SELECT name FROM sqlite_master WHERE type='table' AND name='blobs';" 2>/dev/null || echo "")
    if [[ -n "${blob_table_exists}" ]]; then
        blob_bytes=$(sqlite3 "${db_path}" \
            "SELECT COALESCE(SUM(size), 0) FROM blobs;" 2>/dev/null || echo 0)
        blob_count=$(sqlite3 "${db_path}" \
            "SELECT COUNT(*) FROM blobs;" 2>/dev/null || echo 0)
    fi

    # Upsert into the actor store's account_usage table
    sqlite3 "${db_path}" "
        INSERT OR REPLACE INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count)
        VALUES ('${did}', ${blob_bytes}, ${blob_count}, ${repo_bytes}, ${record_count});
    " 2>/dev/null || echo "Warning: failed to update ${db_path}" >&2

    actor_count=$((actor_count + 1))
    total_records=$((total_records + record_count))
    total_blobs=$((total_blobs + blob_count))
done

echo "Backfill complete."
echo "  Actors processed: ${actor_count}"
echo "  Total records:    ${total_records}"
echo "  Total blobs:      ${total_blobs}"

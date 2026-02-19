#!/bin/bash
# backup_pds.sh — Automated backup for ATProto PDS (NSPds)
#
# Uses SQLite's .backup command for safe, consistent backups of WAL-mode databases.
# Suitable for cron scheduling.
#
# Usage:
#   ./scripts/backup_pds.sh [--data-dir /var/lib/atprotopds/data] [--backup-dir /var/backups/atprotopds]
#
# Cron example (daily at 3am):
#   0 3 * * * /opt/atprotopds/scripts/backup_pds.sh >> /var/log/atprotopds/backup.log 2>&1

set -euo pipefail

# Defaults
DATA_DIR="${PDS_DATA_DIR:-/var/lib/atprotopds/data}"
BACKUP_DIR="${PDS_BACKUP_DIR:-/var/backups/atprotopds}"
RETENTION_DAYS="${PDS_BACKUP_RETENTION_DAYS:-14}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --data-dir)  DATA_DIR="$2"; shift 2 ;;
        --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
        --retention)  RETENTION_DAYS="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--data-dir DIR] [--backup-dir DIR] [--retention DAYS]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate
if [ ! -d "$DATA_DIR" ]; then
    echo "ERROR: Data directory not found: $DATA_DIR"
    exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "ERROR: sqlite3 not found in PATH"
    exit 1
fi

BACKUP_DEST="${BACKUP_DIR}/${TIMESTAMP}"
mkdir -p "$BACKUP_DEST"

echo "=== ATProto PDS Backup ==="
echo "Timestamp:     $TIMESTAMP"
echo "Data dir:      $DATA_DIR"
echo "Backup dest:   $BACKUP_DEST"
echo "Retention:     $RETENTION_DAYS days"
echo ""

ERRORS=0
SERVICE_DB_COUNT=0

# Backup a single SQLite database safely
backup_db() {
    local src="$1"
    local dest="$2"
    local label="$3"

    if [ ! -f "$src" ]; then
        echo "  SKIP: $label (not found)"
        return
    fi
    
    local dest_dir
    dest_dir=$(dirname "$dest")
    mkdir -p "$dest_dir"

    echo -n "  Backing up $label... "
    # Capture stderr to log safely
    if ERROR_MSG=$(sqlite3 "$src" ".backup '$dest'" 2>&1); then
        local size
        size=$(du -h "$dest" | cut -f1)
        echo "OK ($size)"
    else
        echo "FAILED"
        echo "    Reason: $ERROR_MSG"
        ERRORS=$((ERRORS + 1))
    fi
}

# 1. Service database (Critical)
echo "Service databases:"
if [ -f "$DATA_DIR/service.db" ]; then
    backup_db "$DATA_DIR/service.db" "$BACKUP_DEST/service.db" "service.db"
    SERVICE_DB_COUNT=1
elif [ -f "$DATA_DIR/service.sqlite" ]; then
    echo "  NOTE: Using legacy service.sqlite path"
    backup_db "$DATA_DIR/service.sqlite" "$BACKUP_DEST/service.sqlite" "service.sqlite"
    SERVICE_DB_COUNT=1
else
    echo "  FAILED: service.db not found in $DATA_DIR"
    ERRORS=$((ERRORS + 1))
fi

# Sequencer database (if exists)
if [ -f "$DATA_DIR/sequencer.sqlite" ]; then
    backup_db "$DATA_DIR/sequencer.sqlite" "$BACKUP_DEST/sequencer.sqlite" "sequencer.sqlite"
fi

# 2. User databases (stored in hashed DID directories)
echo ""
echo "User databases:"
USER_COUNT=0

# Safer loop using find -print0
while IFS= read -r -d '' db_path; do
    # Skip service/sequencer explicitly if find picks them up (depending on structure)
    if [[ "$db_path" == *"/service.sqlite" ]] || [[ "$db_path" == *"/sequencer.sqlite" ]]; then
        continue
    fi

    # Preserve directory structure relative to DATA_DIR
    rel_path="${db_path#$DATA_DIR/}"
    dest_path="$BACKUP_DEST/$rel_path"

    # Extract DID directory name for labeling (assuming .../did/data.sqlite)
    did_dir=$(basename "$(dirname "$db_path")")
    
    backup_db "$db_path" "$dest_path" "user/$did_dir"
    USER_COUNT=$((USER_COUNT + 1))
done < <(find "$DATA_DIR" -maxdepth 4 -name "data.sqlite" -print0 2>/dev/null)

if [ "$USER_COUNT" -eq 0 ]; then
    echo "  (No user databases found)"
fi

# 3. Configuration backup (non-SQLite, just copy)
echo ""
echo "Configuration:"
for config_file in "$DATA_DIR/../config.json" "$DATA_DIR/../production.json" "/etc/atprotopds/production.json"; do
    if [ -f "$config_file" ]; then
        cp "$config_file" "$BACKUP_DEST/$(basename "$config_file")"
        echo "  Copied $(basename "$config_file")"
    fi
done

# 4. Compress
echo ""
echo -n "Compressing backup... "
ARCHIVE="${BACKUP_DIR}/pds-backup-${TIMESTAMP}.tar.gz"
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" "$TIMESTAMP"
ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo "OK ($ARCHIVE_SIZE)"

# Clean up uncompressed directory
rm -rf "$BACKUP_DEST"

# 5. Prune old backups
echo ""
echo "Pruning backups older than $RETENTION_DAYS days..."
PRUNED=0
# Safer pruning with find -print0
while IFS= read -r -d '' old; do
    echo "  Removed: $(basename "$old")"
    rm -f "$old"
    PRUNED=$((PRUNED + 1))
done < <(find "$BACKUP_DIR" -name "pds-backup-*.tar.gz" -mtime +"$RETENTION_DAYS" -print0)

# Summary
echo ""
echo "=== Backup Complete ==="
echo "Archive: $ARCHIVE"
if [ "$ERRORS" -gt 0 ]; then
    echo "WARNING: $ERRORS database(s) failed to backup"
    exit 1
else
    echo "Status: All databases backed up successfully ($((USER_COUNT + SERVICE_DB_COUNT)) DBs)"
fi

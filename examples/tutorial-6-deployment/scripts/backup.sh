#!/bin/bash
# backup.sh — Wrapper for ATProto PDS backup script
#
# Usage: ./scripts/backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment
if [ -f "$PROJECT_DIR/docker/.env" ]; then
    source "$PROJECT_DIR/docker/.env"
fi

# Defaults
DATA_DIR="${PDS_DATA_DIR:-/var/lib/docker/volumes/pds_pds_data/_data}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/atprotopds}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"

# Find the backup script
BACKUP_SCRIPT=""
if [ -f "$PROJECT_DIR/../../../scripts/backup_pds.sh" ]; then
    BACKUP_SCRIPT="$PROJECT_DIR/../../../scripts/backup_pds.sh"
elif [ -f "/usr/local/bin/backup_pds.sh" ]; then
    BACKUP_SCRIPT="/usr/local/bin/backup_pds.sh"
else
    echo "ERROR: backup_pds.sh not found"
    echo "Expected locations:"
    echo "  - $PROJECT_DIR/../../../scripts/backup_pds.sh"
    echo "  - /usr/local/bin/backup_pds.sh"
    exit 1
fi

# Run backup
exec "$BACKUP_SCRIPT" \
    --data-dir "$DATA_DIR" \
    --backup-dir "$BACKUP_DIR" \
    --retention "$RETENTION_DAYS"

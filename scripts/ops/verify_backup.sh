#!/bin/bash

# verify_backup.sh
#
# Automated backup integrity verification script
# Checks backup file recency, archive integrity, and SQLite database validity
#
# Usage:
#   ./verify_backup.sh [backup_file]
#
# If backup_file not specified, uses latest backup in standard location:
#   /var/backups/atprotopds/pds-backup-latest.tar.gz
#
# Exit codes:
#   0 = Success, backup is valid
#   1 = Error, backup is invalid or missing

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/atprotopds}"
MAX_AGE_SECONDS=86400  # 24 hours
TEMP_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cleanup function
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Determine backup file
if [ -n "$1" ]; then
    BACKUP_FILE="$1"
else
    # Use latest backup
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/pds-backup-*.tar.gz 2>/dev/null | head -1)
    if [ -z "$BACKUP_FILE" ]; then
        log_error "No backup files found in $BACKUP_DIR"
        exit 1
    fi
fi

log_info "Verifying backup: $BACKUP_FILE"
echo ""

# 1. Check file exists
if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi
log_success "Backup file exists"

# 2. Check file size is reasonable (at least 1MB)
FILE_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null)
FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
if [ "$FILE_SIZE_MB" -lt 1 ]; then
    log_error "Backup file too small: ${FILE_SIZE_MB}MB (< 1MB)"
    exit 1
fi
log_success "Backup file size: ${FILE_SIZE_MB}MB"

# 3. Check file age
FILE_TIMESTAMP=$(stat -f%m "$BACKUP_FILE" 2>/dev/null || stat -c%Y "$BACKUP_FILE" 2>/dev/null)
CURRENT_TIMESTAMP=$(date +%s)
AGE=$((CURRENT_TIMESTAMP - FILE_TIMESTAMP))
AGE_HOURS=$((AGE / 3600))
AGE_DAYS=$((AGE / 86400))

if [ "$AGE" -gt "$MAX_AGE_SECONDS" ]; then
    log_error "Backup is too old: ${AGE_HOURS}h ${((AGE%3600)/60)}m (max: 24h)"
    exit 1
fi
log_success "Backup age: ${AGE_HOURS}h ${((AGE%3600)/60)}m old"

# 4. Verify tar.gz archive integrity
log_info "Checking archive integrity..."
if ! tar -tzf "$BACKUP_FILE" > /dev/null 2>&1; then
    log_error "Backup archive is corrupted (cannot list contents)"
    exit 1
fi
log_success "Archive integrity verified"

# 5. Extract to temporary directory and check SQLite databases
log_info "Verifying database integrity..."
TEMP_DIR=$(mktemp -d)

tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" 2>/dev/null || {
    log_error "Failed to extract backup archive"
    exit 1
}

DB_COUNT=0
DB_FAILED=0

# Find all SQLite databases
for db in $(find "$TEMP_DIR" -name "*.db" -o -name "*.sqlite" 2>/dev/null); do
    DB_COUNT=$((DB_COUNT + 1))
    DB_NAME=$(basename "$db")

    # Check SQLite database integrity
    INTEGRITY_CHECK=$(sqlite3 "$db" "PRAGMA integrity_check;" 2>&1 || echo "ERROR")

    if [ "$INTEGRITY_CHECK" = "ok" ]; then
        log_success "Database $DB_NAME: OK"
    else
        log_error "Database $DB_NAME: FAILED"
        log_error "  Details: $INTEGRITY_CHECK"
        DB_FAILED=$((DB_FAILED + 1))
    fi
done

if [ "$DB_COUNT" -eq 0 ]; then
    log_warn "No databases found in backup"
fi

if [ "$DB_FAILED" -gt 0 ]; then
    log_error "$DB_FAILED database(s) failed integrity check"
    exit 1
fi

# 6. Check for required files
log_info "Checking for required files..."

REQUIRED_DIRS=("service" "sequencer" "did_cache")
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$TEMP_DIR/$dir" ]; then
        log_success "Directory present: $dir"
    else
        log_warn "Missing directory: $dir (may be normal if empty)"
    fi
done

# Summary
echo ""
log_success "========================================="
log_success "BACKUP VERIFICATION PASSED"
log_success "========================================="
echo ""
log_info "Summary:"
log_info "  File: $BACKUP_FILE"
log_info "  Age: ${AGE_HOURS}h ${((AGE%3600)/60)}m"
log_info "  Size: ${FILE_SIZE_MB}MB"
log_info "  Databases checked: $DB_COUNT"
log_info "  Databases OK: $((DB_COUNT - DB_FAILED))"

# Bonus: Show backup timestamp and content
BACKUP_TIMESTAMP=$(stat -f%Sm -t '%Y-%m-%d %H:%M:%S' "$BACKUP_FILE" 2>/dev/null || date -d @"$FILE_TIMESTAMP" '+%Y-%m-%d %H:%M:%S')
log_info "  Backup timestamp: $BACKUP_TIMESTAMP"
echo ""

exit 0

#!/bin/sh
# Wintermute entrypoint — wait for PostgreSQL, then start the indexer.
#
# The bsky schema must already exist (created by the bsky-dataplane sidecar
# via Kysely migrations). Wintermute uses ON CONFLICT for all INSERTs, so
# it's safe to start even if the dataplane is still running migrations.

set -e

DB_HOST="${DATABASE_HOST:-local-wintermute-db}"
DB_PORT="${DATABASE_PORT:-5432}"
DB_USER="${DATABASE_USER:-wintermute}"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."
i=0
max_retries=60
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -q 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge "$max_retries" ]; then
        echo "FATAL: PostgreSQL not ready after ${max_retries} retries" >&2
        exit 1
    fi
    echo "PostgreSQL not ready, retrying in 2s... ($i/$max_retries)"
    sleep 2
done
echo "PostgreSQL is ready"

# Start wintermute
echo "Starting wintermute..."
exec wintermute

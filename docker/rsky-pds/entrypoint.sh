#!/bin/bash
set -e

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL at ${DATABASE_URL}..."
until diesel migration run --database-url "${DATABASE_URL}" 2>/dev/null; do
    echo "PostgreSQL not ready yet, retrying in 2s..."
    sleep 2
done
echo "Migrations applied successfully."

# Start the PDS server
exec ./rsky-pds

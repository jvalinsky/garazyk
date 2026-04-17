#!/bin/bash
# reseed_local_network.sh
# Resets the local-network and populates it with test data.

set -e

# Change to repo root
cd "$(dirname "$0")/.."

echo "Stopping local network and wiping volumes..."
docker compose -f docker/local-network/docker-compose.yml down -v

echo "Starting local network..."
docker compose -f docker/local-network/docker-compose.yml up -d

echo "Waiting for services to be healthy..."
# We wait for the last service in the chain (appview) which depends on everything else
timeout 120s bash -c 'until docker inspect --format="{{.State.Health.Status}}" local-appview | grep -q "healthy"; do sleep 2; done'

echo "Creating test accounts..."
# Create alice (DID will be registered in PLC)
docker exec local-pds kaszlak account create --email alice@example.com --handle alice.localhost --password password123
# Create bob
docker exec local-pds kaszlak account create --email bob@example.com --handle bob.localhost --password password123
# Create charlie
docker exec local-pds kaszlak account create --email charlie@example.com --handle charlie.localhost --password password123

echo "PDS accounts created. Verifying PLC directory..."
curl -s http://localhost:2582/_list | grep -o "did:plc:[a-z0-9]*"

echo "Verifying Relay metrics..."
curl -s http://localhost:2584/api/relay/health | grep -q "ok" && echo "Relay is OK"

echo "Verifying AppView status..."
curl -s -H "Authorization: Bearer localdevadmin" http://localhost:3200/admin/backfill/status | grep -q "repos_synced" && echo "AppView is OK"

echo "Local network reseeded successfully."

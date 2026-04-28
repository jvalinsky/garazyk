---
title: "Tutorial 9: Blobs and Migrations"
---

# Tutorial 9: Blobs and Migrations

## Overview

This tutorial covers the management of binary large objects (blobs) and the evolution of the PDS database schema. In Garazyk, binary data is addressed by CID and stored outside the primary database, while the schema itself is managed through a versioned migration system.

You will learn how to:
- Handle blob uploads and content-addressed storage.
- Understand the relationship between the filesystem and the database metadata.
- Safely evolve the database schema using migration providers.

**Learning Objectives:**
- Trace a blob from upload to CID-based storage in `PDSBlobService`.
- Identify the storage layout on disk and its link to actor databases.
- Use `PDSMigrationProvider` to trigger and verify schema updates.
- Monitor migration progress and blob integrity using `deciduous`.

**Estimated Time:** 40-50 minutes

## Prerequisites

- Complete [Tutorial 3: Records](./tutorial-3-records) (understanding IPLD and CIDs).
- Familiarity with the `data/` directory structure.
- Basic understanding of SQLite and SQL DDL (Data Definition Language).
- `deciduous` CLI tool installed and configured.

## What You Will Build

You will walk through the lifecycle of a blob and a schema change:
1. The **Blob Write Path**: From XRPC to disk.
2. The **Migration Loop**: From version detection to commit.
3. **Verification Tooling**: How to prove the system is consistent.

---

## Step 1: Track the Goal with Deciduous

Before modifying storage or schema logic, initialize your work in the `deciduous` graph to ensure every structural change is recorded:

```bash
deciduous add goal "Explore Blobs and Migrations" -c 95
# Track your analysis
deciduous add action "Traced PDSBlobService upload path" -c 90
```

---

## Step 2: Blob Upload and CID Addressing

When a client calls `com.atproto.repo.uploadBlob`, the request is routed to `PDSBlobService`. Unlike records, blobs are not stored in the repository MST; they are stored as standalone files and referenced by CID.

### The Role of `PDSBlobService`
`PDSBlobService` acts as the coordinator. It:
1. **Validates** the MIME type and size.
2. **Streams** the bytes to a temporary location.
3. **Computes the CID** (Content Identifier) using SHA-256.
4. **Commits** the file to permanent storage only if the hash matches.

**Technical Detail:**
CIDs ensure deduplication. If two users upload the same image, the PDS stores the bytes once but records two metadata entries in their respective actor databases.

---

## Step 3: The `data/` Storage Layout

Blobs are stored in a sharded directory structure to avoid filesystem performance bottlenecks.

### Directory Structure
```bash
# Example layout in your data directory
pds-data/
  └── blobs/
      └── sha256/
          └── ab/
              └── cd/
                  └── abcd123... (the raw blob)
```

### Database Mapping
The `PDSBlobService` maintains a mapping in the actor's SQLite database (usually the `blobs` table):
- `cid`: The primary key.
- `mimeType`: Used for serving the blob with correct headers.
- `size`: Used for quota accounting.
- `createdAt`: Timestamp of the upload.

---

## Step 4: Schema Versioning and Migration Triggers

As Garazyk gains features, its database schema must change. `PDSMigrationProvider` manages this evolution by tracking the `schema_version`.

### How Migrations Work
1. **Detection**: On startup, the PDS checks the `schema_version` table.
2. **Comparison**: It compares the current version to the highest available migration file in `Garazyk/Sources/Database/Migration/`.
3. **Execution**: If the database is behind, it executes the pending migrations in order (e.g., `V1 -> V2 -> V3`).

### Triggering a Migration
Migrations are triggered automatically during the PDS bootstrap process. If you add a new migration class:
- Ensure it inherits from the base migration class.
- Implement the `up` method with your SQL changes.
- `PDSMigrationProvider` will find it via reflection or registration.

---

## Troubleshooting

| Failure Mode | Symptom | Mitigation |
| --- | --- | --- |
| **Orphaned Blobs** | Files exist in `blobs/` but no DB entry exists. | Run a `blob audit` to prune unreferenced files. |
| **Transaction Deadlocks** | PDS hangs during a schema migration. | Ensure migrations use short-lived transactions; avoid `ALTER TABLE` on multi-million row tables without care. |
| **CID Mismatch** | `BlobStorage` rejects a read. | Potential bit rot or interrupted write. Re-upload or restore from backup. |
| **Migration Gap** | Database version is higher than code version. | This happens if you roll back code but not the DB. Downgrades are NOT supported; restore a backup. |

## Next Steps

1. Move to [Tutorial 10: Deep-Dive OAuth2 & DPoP](./tutorial-10-oauth-dpop).
2. Review [Blob Lifecycle](../07-repository-protocol/blob-lifecycle) for protocol-level details.
3. Check [Service Databases](../05-database-layer/service-databases) for the full schema map.

## Summary

The blob and migration systems provide the "durability" layer of Garazyk. By using `PDSBlobService` and `PDSMigrationProvider`, the PDS ensures that:
- Binary data is **verifiable** via CIDs.
- Storage is **efficient** via sharding and deduplication.
- Database evolution is **safe** and **ordered**.

Always use `deciduous` to document why a schema change was necessary and how it affects the overall PDS architecture.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

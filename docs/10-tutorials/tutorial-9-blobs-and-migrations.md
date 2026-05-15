---
title: "Tutorial 9: Blobs and Migrations"
---

# Tutorial 9: Blobs and Migrations

This tutorial covers binary large object (blob) management and database schema evolution. Garazyk uses content-addressed storage (CID) for binary data and a versioned migration system for database changes.

## Blob Storage and Addressing

When a client calls `com.atproto.repo.uploadBlob`, the request routes to `PDSBlobService`. Unlike repository records, blobs are stored as standalone files and addressed by their CID.

### The Role of `PDSBlobService`
1. **Validation:** Checks MIME type and size limits.
2. **Streaming:** Writes bytes to a temporary location.
3. **Hashing:** Computes the SHA-256 CID.
4. **Commit:** Moves the file to permanent storage only if the hash matches.

CIDs enable deduplication. If multiple users upload the same image, the PDS stores the bytes once while recording separate metadata entries in each actor's database.

### Storage Layout
Blobs are sharded on disk to maintain filesystem performance:

```bash
pds-data/blobs/sha256/ab/cd/abcd123...
```

The metadata (CID, MIME type, size) is stored in the actor's SQLite database.

## Database Migrations

`PDSMigrationProvider` manages the evolution of the PDS schema.

### How Migrations Work
1. **Detection:** On startup, the PDS checks the `schema_version` table.
2. **Comparison:** It compares the current version against migration files in `Garazyk/Sources/Database/Migration/`.
3. **Execution:** Pending migrations (e.g., `V1 -> V2`) are executed in sequence.

### Adding a Migration
To change the schema:
1. Create a new migration class in the migration directory.
2. Inherit from the base migration class.
3. Implement the `up` method with your SQL changes.

Migrations trigger automatically during the PDS bootstrap process.

## Troubleshooting

| Failure | Symptom | Mitigation |
| --- | --- | --- |
| Orphaned Blobs | Files in `blobs/` with no DB entry | Run a blob audit to prune unreferenced files. |
| Deadlocks | PDS hangs during migration | Keep migration transactions short; avoid long-running `ALTER TABLE` operations. |
| CID Mismatch | `BlobStorage` rejects a read | Likely data corruption. Restore from backup. |
| Version Gap | DB version > code version | Restore a database backup. Downgrades are not supported. |

## See Also

- [Blob Lifecycle](../07-repository-protocol/blob-lifecycle)
- [Service Databases](../05-database-layer/service-databases)
- [Tutorial 3: Records](./tutorial-3-records)

# Database Architecture

Garazyk stores service state and actor repositories in SQLite.

## Layout

Service databases hold shared state such as accounts, DID cache entries, and
sequencer positions. Actor data is split by DID:

```text
<data directory>/
  service/
  did_cache/
  sequencer/
  <DID prefix>/
    <DID>/
      data.sqlite
      <DID>_signing_key.pem
```

Blob files are stored separately.

## Components

| Component                    | Purpose                                           |
| ---------------------------- | ------------------------------------------------- |
| `ActorStore`                 | Records, blocks, repository roots, and actor keys |
| `DatabasePool`               | Opens and reuses actor stores                     |
| `ServiceDatabases`           | Shared service databases                          |
| `PDSMigrationManager`        | Schema migrations                                 |
| `PDSHealthCheck`             | Database health information                       |
| `ATProtoDatabaseQueryRunner` | Parameterized query execution                     |

`ActorStore` exposes reader and transactor protocols. Callers use the reader for
queries and a transactor for grouped writes.

```objc
NSError *error = nil;
[store transactWithBlock:^(id<PDSActorStoreTransactor> transactor) {
    [transactor putRecord:record forDid:did error:&error];
} error:&error];
```

Check errors inside the transaction and stop dependent work when an operation
fails.

## SQLite behavior

Databases use WAL mode. Reads use pooled connections. Writes for a store run
through its write queue.

The schema and indexes are defined by the migration code rather than this
document. Inspect `Schema/`, `Migrations/`, and `PDSMigrationManager.m` before
changing a table.

Repository data includes:

- the current repository root
- records keyed by AT URI
- IPLD blocks keyed by CID

Primary keys cover direct URI and CID lookups. Collection queries use explicit
indexes.

## Migrations

Migrations run in order and record their applied version. Schema changes should
be transactional and safe to retry. Add tests for a new database and for an
upgrade from the previous schema.

The older monolithic migration path remains in `PDSMigrationManager`. Do not run
it against production data without a verified backup.

## Backups

Use SQLite's backup API for databases in WAL mode:

```sh
./scripts/ops/backup_pds.sh \
  --data-dir /var/lib/atprotopds/data \
  --backup-dir /var/backups/atprotopds
```

Verify the resulting archive with `scripts/ops/verify_backup.sh`. Back up local
blob storage separately.

## Changes

When changing this layer:

1. Keep SQL parameterized.
2. Preserve the read and write queue contracts.
3. Add or update a migration.
4. Test rollback behavior on transaction failure.
5. Check query plans when adding a query or index.

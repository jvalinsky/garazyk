# Refactor 6: Legacy Migration Cleanup

## Evidence

**Two migration systems coexist:**

| System | Location | Table | Status |
|--------|----------|-------|--------|
| Legacy | `Database/Migration/PDSMigrationExecutor.h/.m` | `schema_version` | Used by PDSDatabase.m init path |
| Legacy V1 | `Database/Migration/PDSServiceMigration001.h/.m` | — | Ephemeral, applied by executor |
| Legacy V2 | `Database/Migration/PDSServiceMigration002.h/.m` | — | Ephemeral, applied by executor |
| Modern | `Database/Migrations/PDSMigrationManager.h/.m` | `_migrations` | Used by PDSActorStore + ServiceDatabases |
| Modern V1-V8 | `Database/Migrations/PDSMigrationManager.m` | — | Factory method list (line 1399-1416) |

**Filenames:**
- `Migration/` (singular) — legacy, 3 files
- `Migrations/` (plural) — modern, 2 files

This distinction is easy to miss during code review.

## Why It Matters

- Confusing for new developers — which system should a new migration use?
- Legacy migrations V1 and V2 may already be applied on all production databases
- PDSDatabase.m still uses the legacy path, creating subtle divergence from ActorStore databases
- Duality complicates the unified database protocol (Refactor 2)

## Proposed Cleanup

### Step 1: Verify Legacy Migrations Are Redundant

Check if any database on disk still has `schema_version` entries that haven't been migrated to `_migrations`:

```sql
SELECT * FROM schema_version;
SELECT * FROM _migrations;
```

If `schema_version` contains V1/V2 entries on all databases, the legacy path can be removed.

### Step 2: Remove Legacy Migration Files

Delete:
- `Garazyk/Sources/Database/Migration/PDSMigrationExecutor.h/.m`
- `Garazyk/Sources/Database/Migration/PDSServiceMigration001.h/.m`
- `Garazyk/Sources/Database/Migration/PDSServiceMigration002.h/.m`

And the corresponding `PDSDatabaseMigration` protocol.

### Step 3: Update PDSDatabase.m

Replace the legacy migration call in `PDSDatabase.m`'s `-openWithError:` path with a call to `PDSMigrationManager`:

```objc
// Before:
PDSMigrationExecutor *executor = [[PDSMigrationExecutor alloc] init];
[executor runMigrationOnDatabase:self];

// After:
PDSMigrationManager *manager = [PDSMigrationManager migrationManagerForDatabase:self];
[manager applyPendingMigrations:&error];
```

This makes PDSDatabase consistent with ActorStore.

### Step 4: Clean Up Directory Structure

- Remove empty `Database/Migration/` directory
- Keep `Database/Migrations/` (plural) as the canonical location

### Step 5: Update CMakeLists.txt

Remove the legacy migration files from `ATPROTO_STORAGE_SOURCES` glob or explicit list.

## Rollback

Each file removal can be reverted individually. The functional change is in Step 3 (PDSDatabase.m migration path) — everything else is file deletion.

## Dependencies

- Requires verifying legacy migrations are redundant against production databases
- After Refactor 1 (PDSDatabase decomposition) for cleaner PDSDatabase.m
- Before or alongside Refactor 2 (unified DB protocol)

## Confidence: High

Both systems are well-understood. The modern system already handles all current V1-V8 migrations. The legacy executor wraps the same migration logic.

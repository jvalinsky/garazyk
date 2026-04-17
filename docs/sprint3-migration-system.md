# Sprint 3 Database Migration System

## Overview

The migration system provides schema version tracking, transaction-safe migrations, and rollback support for the garazyk ATProtoPDS.

## Architecture

### Components

1. **PDSMigration Protocol** (`Database/Migrations/PDSMigration.h`)
   - Defines `up:` and `down:` methods for forward/backward migrations
   - Each migration has a version number and name
   - Returns detailed errors on failure

2. **PDSMigrationManager** (`Database/Migrations/PDSMigrationManager.{h,m}`)
   - Tracks applied migrations in `_migrations` table
   - Applies pending migrations in version order
   - Supports rollback to specific versions
   - Transaction-wrapped for safety

3. **V1 Initial Schema** (Embedded in PDSMigrationManager.m)
   - Creates actor store or service database schema
   - Uses PDSSchemaManager for schema definitions
   - Fully reversible with DROP TABLE

## Usage

### Actor Store Migration

```objc
PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];
NSError *error = nil;
if (![manager migrateDatabase:db error:&error]) {
    NSLog(@"Migration failed: %@", error);
}
```

### Service Database Migration

```objc
PDSMigrationManager *manager = [PDSMigrationManager serviceDatabaseMigrationManager];
NSError *error = nil;
if (![manager migrateDatabase:db error:&error]) {
    NSLog(@"Migration failed: %@", error);
}
```

### Rollback

```objc
// Rollback to version 0 (removes all tables)
if (![manager rollbackToVersion:db version:0 error:&error]) {
    NSLog(@"Rollback failed: %@", error);
}
```

### Check Version

```objc
NSInteger currentVersion = [manager currentVersion:db];
NSArray *pending = [manager pendingMigrations:db];
```

## Migration Table Schema

```sql
CREATE TABLE _migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at REAL NOT NULL
);
```

## Integration Points

### ActorStore.m (createSchema:)

Previously created schema inline with backward-compatible column additions.

**Now**: Uses migration manager for clean schema initialization:

```objc
- (BOOL)createSchema:(NSError **)error {
    PDSMigrationManager *manager = [PDSMigrationManager actorStoreMigrationManager];

    // Check for legacy database
    if (!hasMigrationsTable && hasTables) {
        // Reject - fresh installs only
        return NO;
    }

    // Run pending migrations
    return [manager migrateDatabase:self.db error:error];
}
```

### ServiceDatabases.m (initializeServiceSchema:)

Previously called PDSSchemaManager directly.

**Now**: Uses migration manager:

```objc
- (BOOL)initializeServiceSchema:(NSError **)error {
    PDSActorStore *store = [self.servicePool storeForDid:@"__service__" error:error];
    if (!store) return NO;

    PDSMigrationManager *manager = [PDSMigrationManager serviceDatabaseMigrationManager];
    return [manager migrateDatabase:store.db error:error];
}
```

## Testing

Migration tests verify:

1. **testFreshInstall**: Fresh database creation
2. **testRollback**: Rollback to version 0
3. **testReApply**: Rollback then re-apply

Run tests:
```bash
cmake --build build --target migration_tests
./build/bin/migration_tests
```

## Key Design Decisions

1. **Fresh installs only** - No support for migrating pre-existing databases without `_migrations` table
2. **Both up and down migrations** - Rollback support from day one
3. **Transaction safety** - Each migration wrapped in BEGIN/COMMIT
4. **Version tracking** - `_migrations` table prevents re-application
5. **Embedded V1 schema** - No separate SQL files needed

## Future Enhancements

- Add CLI command for manual rollback: `kaszlak migrate --rollback-to 0`
- Add more V2+ migrations for schema changes
- Consider SQL migration files for large schema changes
- Add migration history query API

## Sprint 3 Status

- [x] Phase 1: Database Migration Framework (COMPLETE)
- [ ] Phase 2: Logging Standardization
- [ ] Phase 3: Performance Optimization
- [ ] Phase 4: Production Checklist

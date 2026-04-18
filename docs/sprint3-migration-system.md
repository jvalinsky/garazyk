# Sprint 3: Database Migration System

## Overview

The migration system provides automatic schema version tracking and transaction-safe migrations for the ATProto PDS. It enables forward-compatible schema evolution while maintaining backward compatibility with existing databases.

**Status**: ✅ Implemented in Sprint 3 (Phase 2)

## Architecture

### Components

1. **PDSDatabaseMigration Protocol** (`Database/Migration/PDSDatabaseMigration.h`)
   - Defines the interface for implementing schema migrations
   - Properties: `version` (NSInteger), `description` (NSString)
   - Method: `applyToDatabase:error:` - executes the migration

2. **PDSMigrationExecutor** (`Database/Migration/PDSMigrationExecutor.{h,m}`)
   - Manages migration execution and version tracking
   - `currentVersionOfDatabase:error:` - queries MAX(version) from schema_version table
   - `executePendingMigrationsOnDatabase:migrations:error:` - executes pending migrations in transaction
   - Implements transaction safety with automatic rollback on failure
   - Thread-safe through database transaction locking

3. **PDSServiceMigration001** (`Database/Migration/PDSServiceMigration001.{h,m}`)
   - Initial migration that creates the schema_version table
   - Idempotent - safe to run on existing databases
   - Enables all future migrations to track versions

4. **PDSSchemaManager** (Updated - `Database/Schema/PDSSchemaManager.m`)
   - New method: `schemaVersionTableSQL` - SQL for schema_version table
   - Updated: `serviceSchemaSQL` - includes schema_version table
   - Updated: `actorStoreSchemaSQL` - includes schema_version table

## Schema Version Tracking

### schema_version Table

```sql
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at DATETIME NOT NULL DEFAULT (datetime('now')),
    description TEXT NOT NULL
);
```

- **version**: Sequential migration version number (1, 2, 3, ...)
- **applied_at**: Timestamp when migration was applied (automatic)
- **description**: Human-readable migration description

## Usage

### Creating a New Migration

Implement the PDSDatabaseMigration protocol:

```objc
@interface MyMigration002 : NSObject <PDSDatabaseMigration>
@end

@implementation MyMigration002

- (NSInteger)version {
    return 2;
}

- (NSString *)description {
    return @"Add new column to accounts table";
}

- (BOOL)applyToDatabase:(PDSDatabase *)database error:(NSError **)error {
    NSString *sql = @"ALTER TABLE accounts ADD COLUMN new_field TEXT";
    return [database executeUpdate:sql params:@[] error:error];
}

@end
```

### Registering Migrations

In `PDSDatabase.m` `openWithError:`:

```objc
PDSMigrationExecutor *executor = [[PDSMigrationExecutor alloc] init];
NSArray *migrations = @[
    [[PDSServiceMigration001 alloc] init],
    [[MyMigration002 alloc] init],
    // Add future migrations here
];
if (![executor executePendingMigrationsOnDatabase:self migrations:migrations error:error]) {
    PDS_LOG_DB_ERROR(@"Failed to execute pending migrations: %@", *error);
    return NO;
}
```

## How It Works

1. **Database Opens**: `PDSDatabase.openWithError:` is called
2. **Schema Created**: `createSchema:error` creates tables via CREATE TABLE IF NOT EXISTS
3. **Migrations Execute**: PDSMigrationExecutor checks current version and runs pending migrations
4. **Transactions**: Each migration runs in a database transaction (automatic rollback on failure)
5. **Versioning**: Successful migrations recorded in schema_version table

## Integration Points

### PDSDatabase.m (openWithError:)

After `createSchema:error:`, migrations run automatically:

```objc
[self createSchema:error];

// Run migrations
PDSMigrationExecutor *executor = [[PDSMigrationExecutor alloc] init];
NSArray *migrations = @[[[PDSServiceMigration001 alloc] init], ...];
if (![executor executePendingMigrationsOnDatabase:self migrations:migrations error:error]) {
    return NO;
}
```

### PDSSchemaManager.m

Schema definitions now include version tracking table:

```objc
- (NSString *)serviceSchemaSQL {
    NSMutableString *sql = [NSMutableString string];
    // ... existing tables ...
    [sql appendString:[self schemaVersionTableSQL]];
    return sql;
}

- (NSString *)schemaVersionTableSQL {
    return @"CREATE TABLE IF NOT EXISTS schema_version ("
           @"    version INTEGER PRIMARY KEY,"
           @"    applied_at DATETIME NOT NULL DEFAULT (datetime('now')),"
           @"    description TEXT NOT NULL"
           @")";
}
```

## Key Design Decisions

### 1. Code-Based Migrations (vs. SQL Files)

**Why code-based**:
- Type safety with compile-time checks
- Can include complex logic (data transformations, validation)
- Follows existing Objective-C patterns
- Easier to test than SQL files

### 2. Protocol-Based Design

**Why protocols**:
- Extensible - new migrations just implement the protocol
- Type-safe - compiler checks method signatures
- Testable - can mock migrations easily
- Simple - minimal boilerplate

### 3. Automatic Execution on Startup

**Why automatic**:
- Zero operational overhead
- Databases always in correct state
- No manual migration commands needed
- Transparent to application code

### 4. Transaction Safety

**Why transactions**:
- All-or-nothing semantics
- Automatic rollback on failure
- Database never left in inconsistent state

### 5. Idempotent Initial Migration

**Why V1 is special**:
- Doesn't change schema (tables already created via CREATE IF NOT EXISTS)
- Safe to run on existing databases
- Establishes version tracking for all future migrations
- Existing databases automatically upgrade to version 1

## Backward Compatibility

✅ **Fully backward compatible**:
- Existing databases are automatically upgraded to version 1
- No manual intervention required
- schema_version table is created by initial migration
- All future migrations optional (deferred migrations supported)

## Error Handling

Migrations fail safely:

```objc
// If migration fails, transaction rolls back automatically
// Database remains in consistent state
// Error returned to caller with details
// Application can handle appropriately (log, alert, graceful shutdown, etc.)
```

## Testing

Migration executor includes proper error handling for testing:

1. **testMigrationExecutesOnce**: Verify migration runs only once
2. **testMigrationRollbackOnFailure**: Verify rollback on failure
3. **testMigrationsExecuteInOrder**: Verify version ordering

## Logging Integration

Migrations log progress via PDS_LOG_DB_*:

```objc
PDS_LOG_DB_INFO(@"Applying migration %ld: %@", (long)migration.version, migration.description);
PDS_LOG_DB_INFO(@"Migration %ld applied successfully", (long)migration.version);
PDS_LOG_DB_ERROR(@"Migration %ld failed: %@", (long)migration.version, *txError);
```

## Future Enhancements

1. **CLI Commands**: Manual migration commands (check version, apply, rollback)
2. **Dry Run Mode**: Test migrations without applying changes
3. **Conditional Migrations**: Skip migrations based on conditions
4. **Pre/Post Hooks**: Run code before/after migrations
5. **Data Validation**: Verify data integrity after migrations
6. **Migration History**: Query/report on applied migrations

## Files Changed

- `Garazyk/Sources/Database/Migration/PDSDatabaseMigration.h` (new)
- `Garazyk/Sources/Database/Migration/PDSMigrationExecutor.h` (new)
- `Garazyk/Sources/Database/Migration/PDSMigrationExecutor.m` (new)
- `Garazyk/Sources/Database/Migration/PDSServiceMigration001.h` (new)
- `Garazyk/Sources/Database/Migration/PDSServiceMigration001.m` (new)
- `Garazyk/Sources/Database/Schema/PDSSchemaManager.m` (updated)
- `Garazyk/Sources/Database/PDSDatabase.m` (updated)

## Sprint 3 Status

- [x] Phase 1: Logging Standardization (20 NSLog → PDS_LOG_* replacements)
- [x] Phase 2: Database Migration Infrastructure (schema versioning + executor)
- [o] Phase 3: Rate Limiter Optimization (deferred to Sprint 4)
- [x] Phase 4: Testing and Documentation

**Complete**: Production-ready migration infrastructure with automatic startup execution, transaction safety, and backward compatibility.

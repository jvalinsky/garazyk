# WAL Mode

## Overview

Write-Ahead Logging (WAL) is a SQLite journaling mode that improves concurrency and performance. Instead of writing changes directly to the database file, WAL writes changes to a separate log file first, allowing readers to continue accessing the database while writes are in progress.

## WAL Architecture

```
Traditional Mode:
┌─────────────────────────────────────┐
│ Database File (db.sqlite)           │
│ ┌─────────────────────────────────┐ │
│ │ Data                            │ │
│ │ (readers blocked during writes) │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘

WAL Mode:
┌──────────────────────────────────────────────────────────┐
│ Database File (db.sqlite)                                │
│ ┌────────────────────────────────────────────────────┐   │
│ │ Data (readers can access)                          │   │
│ └────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────┐
│ WAL File (db.sqlite-wal)                                 │
│ ┌────────────────────────────────────────────────────┐   │
│ │ Write-ahead log entries                            │   │
│ │ (writers append here)                              │   │
│ └────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────┐
│ Checkpoint File (db.sqlite-shm)                          │
│ ┌────────────────────────────────────────────────────┐   │
│ │ Shared memory for coordination                     │   │
│ └────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

## Configuration

All PDS databases use WAL mode with optimized settings:

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA wal_autocheckpoint=1000;
PRAGMA cache_size=-64000;  /* 64MB cache */
```

### PRAGMA Explanations

| PRAGMA | Value | Purpose |
|--------|-------|---------|
| `journal_mode` | WAL | Enable Write-Ahead Logging |
| `synchronous` | NORMAL | Balance safety and performance |
| `wal_autocheckpoint` | 1000 | Checkpoint after 1000 WAL pages |
| `cache_size` | -64000 | 64MB in-memory cache |

## How WAL Works

### Write Operation

```
1. Writer acquires write lock
   ↓
2. Changes written to WAL file
   ↓
3. WAL file is fsync'd to disk
   ↓
4. Commit record written to WAL
   ↓
5. Write lock released
   ↓
6. Readers can now see changes
```

### Read Operation

```
1. Reader checks WAL file
   ↓
2. Determines which version to read
   ↓
3. Reads from database file + WAL file as needed
   ↓
4. Returns consistent snapshot
```

### Checkpoint Operation

```
1. Checkpoint process acquires checkpoint lock
   ↓
2. Waits for all readers to finish
   ↓
3. Copies WAL entries to database file
   ↓
4. Truncates WAL file
   ↓
5. Releases checkpoint lock
```

## Benefits

### Concurrency

Multiple readers can access the database while a writer is making changes:

```
Time →
Writer:  [Write] [Write] [Write] [Commit]
Reader1:         [Read]  [Read]  [Read]
Reader2:                 [Read]  [Read]
Reader3:                         [Read]
```

### Performance

- Writes are faster (append-only to WAL)
- Readers don't block writers
- Batch writes are more efficient
- Reduced disk I/O

### Reliability

- Atomic commits (all-or-nothing)
- Crash recovery is simpler
- No partial writes to database

## Configuration for PDS

### Service Databases

```objc
// In PDSServiceDatabases initialization
[database executeUpdate:@"PRAGMA journal_mode=WAL"];
[database executeUpdate:@"PRAGMA synchronous=NORMAL"];
[database executeUpdate:@"PRAGMA wal_autocheckpoint=1000"];
[database executeUpdate:@"PRAGMA cache_size=-64000"];
```

### Actor Databases

```objc
// In PDSActorDatabase initialization
[database executeUpdate:@"PRAGMA journal_mode=WAL"];
[database executeUpdate:@"PRAGMA synchronous=NORMAL"];
[database executeUpdate:@"PRAGMA wal_autocheckpoint=1000"];
[database executeUpdate:@"PRAGMA cache_size=-64000"];
```

## Checkpoint Strategies

### Automatic Checkpoint

WAL automatically checkpoints after 1000 pages:

```sql
PRAGMA wal_autocheckpoint=1000;
```

### Manual Checkpoint

Explicitly checkpoint when needed:

```objc
NSError *error = nil;
[database executeUpdate:@"PRAGMA wal_checkpoint(RESTART)" error:&error];
```

### Checkpoint Modes

| Mode | Behavior |
|------|----------|
| PASSIVE | Checkpoint without blocking readers |
| FULL | Wait for readers to finish |
| RESTART | Restart WAL after checkpoint |
| TRUNCATE | Truncate WAL file after checkpoint |

## Monitoring WAL

### Check WAL Status

```objc
NSArray *result = [database executeQuery:@"PRAGMA journal_mode"];
NSLog(@"Journal mode: %@", result[0][@"journal_mode"]);

result = [database executeQuery:@"PRAGMA wal_autocheckpoint"];
NSLog(@"WAL autocheckpoint: %@", result[0][@"wal_autocheckpoint"]);
```

### Monitor WAL File Size

```objc
NSString *walPath = [NSString stringWithFormat:@"%@-wal", databasePath];
NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:walPath error:nil];
NSNumber *fileSize = attrs[NSFileSize];
NSLog(@"WAL file size: %@ bytes", fileSize);
```

### Check for Checkpoint Issues

```objc
// If WAL file grows too large, checkpoint may be blocked
NSError *error = nil;
[database executeUpdate:@"PRAGMA wal_checkpoint(TRUNCATE)" error:&error];

if (error) {
    NSLog(@"Checkpoint failed: %@", error);
}
```

## Performance Tuning

### Cache Size

Larger cache improves performance:

```sql
PRAGMA cache_size=-64000;  /* 64MB */
```

Adjust based on available memory:

```sql
PRAGMA cache_size=-128000;  /* 128MB for high-traffic servers */
```

### Synchronous Mode

Different synchronous modes balance safety and performance:

| Mode | Safety | Performance |
|------|--------|-------------|
| OFF | Low | High |
| NORMAL | Medium | Medium |
| FULL | High | Low |

For PDS, NORMAL is recommended:

```sql
PRAGMA synchronous=NORMAL;
```

### WAL Autocheckpoint

Adjust checkpoint frequency:

```sql
PRAGMA wal_autocheckpoint=1000;  /* Default */
PRAGMA wal_autocheckpoint=5000;  /* Less frequent, larger WAL */
PRAGMA wal_autocheckpoint=100;   /* More frequent, smaller WAL */
```

## Troubleshooting

### WAL File Grows Too Large

**Symptom:** WAL file (db.sqlite-wal) grows to gigabytes

**Cause:** Checkpoint is blocked by long-running readers

**Solution:**
```objc
// 1. Identify long-running queries
// 2. Optimize or cancel them
// 3. Manually checkpoint
NSError *error = nil;
[database executeUpdate:@"PRAGMA wal_checkpoint(TRUNCATE)" error:&error];
```

### Checkpoint Fails

**Symptom:** "database is locked" errors

**Cause:** Readers are still accessing database

**Solution:**
```objc
// 1. Wait for readers to finish
// 2. Use PASSIVE checkpoint mode
NSError *error = nil;
[database executeUpdate:@"PRAGMA wal_checkpoint(PASSIVE)" error:&error];
```

### WAL Corruption

**Symptom:** "database disk image is malformed" errors

**Cause:** Crash during WAL operations

**Solution:**
```objc
// 1. Close database
// 2. Delete WAL files
NSFileManager *fm = [NSFileManager defaultManager];
[fm removeItemAtPath:[NSString stringWithFormat:@"%@-wal", databasePath] error:nil];
[fm removeItemAtPath:[NSString stringWithFormat:@"%@-shm", databasePath] error:nil];

// 3. Reopen database (will rebuild from main file)
```

## Best Practices

1. **Configuration**
   - Always enable WAL mode
   - Use NORMAL synchronous mode
   - Set appropriate cache size
   - Configure autocheckpoint

2. **Monitoring**
   - Monitor WAL file size
   - Track checkpoint frequency
   - Alert on checkpoint failures
   - Monitor reader/writer concurrency

3. **Maintenance**
   - Periodically checkpoint
   - Monitor for long-running queries
   - Clean up WAL files on startup
   - Test crash recovery

4. **Performance**
   - Batch writes together
   - Use transactions for multiple operations
   - Avoid long-running readers
   - Monitor cache hit rate

5. **Deployment**
   - Test WAL on staging
   - Monitor after enabling
   - Have rollback plan
   - Document configuration

## Common Patterns

### Enabling WAL on Existing Database

```objc
NSError *error = nil;

// 1. Close all connections
[database close];

// 2. Delete WAL files if they exist
NSFileManager *fm = [NSFileManager defaultManager];
[fm removeItemAtPath:[NSString stringWithFormat:@"%@-wal", databasePath] error:nil];
[fm removeItemAtPath:[NSString stringWithFormat:@"%@-shm", databasePath] error:nil];

// 3. Reopen and enable WAL
[database open];
[database executeUpdate:@"PRAGMA journal_mode=WAL" error:&error];
[database executeUpdate:@"PRAGMA synchronous=NORMAL" error:&error];
[database executeUpdate:@"PRAGMA wal_autocheckpoint=1000" error:&error];
[database executeUpdate:@"PRAGMA cache_size=-64000" error:&error];
```

### Periodic Checkpoint

```objc
// Checkpoint every 5 minutes
dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                 0, 0,
                                                 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));

dispatch_source_set_timer(timer,
                         dispatch_time(DISPATCH_TIME_NOW, 5*60*NSEC_PER_SEC),
                         5*60*NSEC_PER_SEC,
                         60*NSEC_PER_SEC);

dispatch_source_set_event_handler(timer, ^{
    NSError *error = nil;
    [database executeUpdate:@"PRAGMA wal_checkpoint(PASSIVE)" error:&error];
    
    if (error) {
        NSLog(@"Checkpoint failed: %@", error);
    }
});

dispatch_resume(timer);
```

### Monitoring WAL Health

```objc
- (NSDictionary *)getWALHealth {
    NSMutableDictionary *health = [NSMutableDictionary dictionary];
    
    // Check WAL file size
    NSString *walPath = [NSString stringWithFormat:@"%@-wal", databasePath];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:walPath error:nil];
    health[@"wal_size"] = attrs[NSFileSize] ?: @0;
    
    // Check journal mode
    NSArray *result = [database executeQuery:@"PRAGMA journal_mode"];
    health[@"journal_mode"] = result[0][@"journal_mode"];
    
    // Check synchronous mode
    result = [database executeQuery:@"PRAGMA synchronous"];
    health[@"synchronous"] = result[0][@"synchronous"];
    
    // Check cache size
    result = [database executeQuery:@"PRAGMA cache_size"];
    health[@"cache_size"] = result[0][@"cache_size"];
    
    return health;
}
```

## See Also

- [Service Databases](./service-databases)
- [Actor Databases](./actor-databases)
- [Migrations](./migrations)
- [SQLite Architecture](./sqlite-architecture)

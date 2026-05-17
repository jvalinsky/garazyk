# Objective-C Tips & Best Practices

## Defensive SQLite Programming

When working with SQLite in Objective-C (or C), manual resource management is a common source of
bugs. Forgetting to call `sqlite3_finalize()` on a prepared statement can lead to memory leaks,
while calling it too early or twice can cause crashes.

To mitigate these risks, we use a RAII (Resource Acquisition Is Initialization) pattern leveraging
Clang's `__attribute__((cleanup))` feature.

### Automatic Statement Finalization

We have defined a macro `PDS_SQLITE_AUTORELEASE_STMT` in `Database/Utils/PDSSQLiteUtils.h`. Use this
macro when declaring a `sqlite3_stmt *` variable.

**Example Usage:**

```objective-c
#import "Database/Utils/PDSSQLiteUtils.h"

- (void)fetchData {
    NSString *sql = @"SELECT * FROM items";
    
    // The statement will be automatically finalized when this variable goes out of scope
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            // Process row...
        }
    }
    
    // No need to call sqlite3_finalize(stmt)! 
    // It happens automatically here.
}
```

### Important rules:

1. **Do NOT call `sqlite3_finalize(stmt)` manually** if you use the macro. Doing so will cause a
   double-free when the scope ends.
2. This is best used for **local, transient statements**. For long-lived or cached statements
   (stored in ivars), you must still manage their lifecycle manually or use a different wrapper.
3. Ensure `sqlite3_stmt *` is initialized to `NULL` if not immediately assigned, though
   `sqlite3_prepare_v2` typically handles this.

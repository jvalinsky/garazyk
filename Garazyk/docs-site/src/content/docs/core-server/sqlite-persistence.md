---
title: SQLite Persistence
description: WAL mode, Connection Pooling, and maximizing concurrent disk I/O in ATProtoPDS
---

The ATProtocol is fundamentally a massively replicated, cryptographically authenticated data store.
Everything from a user's complex local relational repository structure (Merkle Search Trees) to the
remote binary blobs they actively sync must be stored securely and persistently on the local disk of
the PDS.

To achieve maximum absolute performance and minimum memory footprint without the massive GC overhead
of a high-level ORM mapping abstraction, `ATProtoPDS` deliberately utilizes raw C-level SQLite
(`#include <sqlite3.h>`) mapped directly to a custom, heavily-optimized thread-safe Objective-C
`DatabasePool`.

## Multi-Version Concurrency (WAL)

The primary catastrophic bottleneck for a standard, out-of-the-box SQLite database running inside a
highly-concurrent web server environment is the dreaded `SQLITE_BUSY` error.

By default, SQLite uses a legacy rollback journal. This architecture physically locks the _entire
database file descriptor_ exclusively during any mutating write transaction, forcing all parallel
reads to violently block until the write gracefully finishes. In a PDS where thousands of WebSocket
clients might be aggressively polling the database, a single slow write block will catastrophically
stall the entire read queue, taking the server offline.

To aggressively defeat this, `ATProtoPDS` boots absolutely all `ActorStore`, `PLCPersistentStore`,
and `Session` SQLite databases into strictly mandated **Write-Ahead Logging** mode immediately upon
physical instantiation:

```c
// Booting the C-level SQLite connection instance
sqlite3_exec(db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);

// Enhance query time by mapping crucial metadata into RAM
sqlite3_exec(db, "PRAGMA mmap_size=268435456;", NULL, NULL, NULL); // 256MB memory mapping
```

### How WAL Unlocks Concurrency

Under strict WAL mode, the SQLite engine physically separates the incoming mutating system writes
into an entirely separate append-only log file on disk (`username.db-wal`) rather than immediately
attempting to destructively overwrite the main `.db` file in place.

This brilliant architectural shift allows **exactly one writer and infinite multiple concurrent
readers simultaneously**! Since readers pull from the main file and writers append strictly to the
WAL file, there is physically zero lock contention between a `SELECT` and an `INSERT`. The
background SQLite checkpointing thread handles mechanically merging the WAL back into the main `.db`
file transparently.

---

## The `DatabasePool` Architecture

In Objective-C, we harness the extreme power of WAL mode by natively implementing an advanced,
generic multi-connection pool wrapping the raw `sqlite3` C pointers:

1. **Read Pool (The Readers):** We proactively maintain an elastic pool of pre-opened `sqlite3 *`
   connection pointers dedicated exclusively to read-only `SELECT` statements. Because WAL mode
   mathematically permits parallel reads against the same physical disk bytes, dozens of globally
   concurrent HTTP threads can asynchronously borrow these connections simultaneously without ever
   spinning on a POSIX lock.
2. **Write Connection (The Synchronized Writer):** We strictly maintain a single, dedicated
   `sqlite3 *` connection physically mapped natively to a single GCD Serial Queue. Any `INSERT`,
   `UPDATE`, or `DELETE` query anywhere across the entire PDS application codebase for a specific
   database is meticulously funneled onto this exact serial queue constraint.

```objc
- (void)asyncRead:(void(^)(sqlite3 *db))block {
    // 1. Instantly borrow an available connection from the concurrent in-memory read-pool
    sqlite3 *conn = [self borrowReader];
    @try {
        // 2. Execute the calling thread's SQL block natively against the connection
        block(conn);
    } @finally {
        // 3. Guarantee we return it safely for the very next incoming 
        //    HTTP request to reuse, even if the block violently throws an exception.
        [self returnReader:conn];
    }
}
```

### Write Safety Guarantees

Because all mutating writes are channeled through the dedicated serial queue abstraction, the
Objective-C developer simply calls `asyncWrite` without ever having to manually write
`sqlite3_mutex_enter()` or manually manage SQL-level `BEGIN TRANSACTION EXCLUSIVE` boundaries. The
GCD queue intrinsically guarantees mathematically that two `sqlite3_step()` calls will never collide
mid-write.

This beautifully ensures infinite read-throughput performance when thousands of federated Bluesky
AppViews are aggressively polling a user's local repository via the WebSocket Firehose
simultaneously.

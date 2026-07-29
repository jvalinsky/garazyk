---
title: SQLite Persistence
description: WAL mode, connection pooling, and transaction boundaries in Garazyk PDS
---

Garazyk stores service metadata and actor repositories in SQLite. The storage
layer uses the SQLite C API through Objective-C connection managers, pools,
repositories, and query runners.

## Multi-Version Concurrency (WAL)

The default database configurations request write-ahead logging (WAL),
`synchronous=NORMAL`, and a busy timeout. WAL allows readers to keep a stable
snapshot while a writer appends changes to the WAL file. SQLite still permits
only one writer at a time, so write coordination remains necessary.

```c
sqlite3_exec(db, "PRAGMA journal_mode=WAL", NULL, NULL, NULL);
sqlite3_exec(db, "PRAGMA synchronous=NORMAL", NULL, NULL, NULL);
sqlite3_busy_timeout(db, 5000);
```

Checkpointing later copies committed WAL pages back into the main database.
Long-running readers can delay checkpoint progress, so callers should keep read
transactions short.

## Connection managers and pools

`ATProtoConnectionPool` owns a bounded set of connections for one database file.
Callers acquire a connection, use it within a defined scope, and return it to
the pool. The pool applies the configured journal mode, synchronization level,
busy timeout, and other PRAGMAs to every connection.

```objc
sqlite3 *connection = [pool acquireConnectionWithTimeout:5.0];
if (connection != NULL) {
    // Use the connection only within this ownership scope.
    [pool releaseConnection:connection];
}
```

`ATProtoConnectionManagerSerial` runs operations on one serialized connection.
`ATProtoConnectionManagerPooled` borrows connections and serializes write
transactions before issuing `BEGIN IMMEDIATE`. The immediate transaction
reserves SQLite's writer slot before a block performs a read and then attempts a
write.

## Query and transaction boundary

`ATProtoDatabaseQueryRunner` prepares statements, binds positional values,
converts result columns to Foundation objects, and translates failures into a
service error domain. Its transaction API provides an
`ATProtoDatabaseTransactor` instead of exposing the raw `sqlite3 *`:

```objc
NSError *error = nil;
BOOL committed = [runner performWriteTransaction:^BOOL(
    id<ATProtoDatabaseTransactor> tx,
    NSError **error
) {
    return [tx executeUpdate:@"UPDATE repos SET active = 1 WHERE did = ?"
                      params:@[did]
                       error:error];
} error:&error];
```

Returning `NO` rolls the transaction back. Reads through the same transactor
observe earlier writes in that transaction.

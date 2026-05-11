// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSConnectionPool.h

 @abstract SQLite connection pooling for improved performance.

 @discussion Manages a pool of database connections to avoid the overhead
 of opening/closing connections repeatedly. Thread-safe with automatic
 connection recycling.

 Connection pooling is essential for performance:
 - Opening SQLite connections is expensive (~1-5ms per connection)
 - Reusing connections reduces latency
 - Pool prevents connection exhaustion
 - Automatic cleanup of idle connections

 Pool behavior:
 - Min connections: maintained permanently
 - Max connections: upper limit during peak load
 - Idle timeout: close connections above min after 60s
 - Thread-safe: dispatch_queue with serial access

 Usage:
 @code
 PDSConnectionPool *pool = [[PDSConnectionPool alloc]
     initWithPath:@"/path/to/db.sqlite" minConnections:2 maxConnections:10];

 sqlite3 *conn = [pool acquireConnection];
 // ... use connection ...
 [pool releaseConnection:conn];
 @endcode

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSConnectionPool

 @abstract Thread-safe SQLite connection pool.

 @discussion Provides connection pooling for a single database file.
 Each pool manages connections to one database. Different databases
 require separate pools.

 Thread-safety: All methods are thread-safe via dispatch_queue.
 */
@interface PDSConnectionPool : NSObject

#pragma mark - Initialization

/*!
 @method initWithPath:minConnections:maxConnections:

 @abstract Initialize pool with database path and size limits.

 @param path Path to SQLite database file.
 @param minConnections Minimum connections to maintain (default: 2).
 @param maxConnections Maximum connections allowed (default: 10).
 @return Initialized pool instance, or nil on error.
 */
- (instancetype)initWithPath:(NSString *)path
              minConnections:(NSUInteger)minConnections
              maxConnections:(NSUInteger)maxConnections;

/*!
 @method initWithPath:

 @abstract Initialize pool with default sizes (min: 2, max: 10).

 @param path Path to SQLite database file.
 @return Initialized pool instance, or nil on error.
 */
- (instancetype)initWithPath:(NSString *)path;

#pragma mark - Connection Management

/*!
 @method acquireConnection

 @abstract Get a connection from the pool.

 @discussion Blocks if max connections reached and none available.
 Connection must be returned via releaseConnection:.

 @return SQLite connection, or NULL on error.
 */
- (sqlite3 * _Nullable)acquireConnection;

/*!
 @method acquireConnectionWithTimeout:

 @abstract Get a connection with a timeout.

 @param timeoutSeconds Maximum time to wait for connection.
 @return SQLite connection, or NULL if timeout expired.
 */
- (sqlite3 * _Nullable)acquireConnectionWithTimeout:(NSTimeInterval)timeoutSeconds;

/*!
 @method releaseConnection:

 @abstract Return a connection to the pool.

 @discussion After calling this, the connection should not be used.
 Connection may be reused by other threads.

 @param connection The connection to return.
 */
- (void)releaseConnection:(sqlite3 *)connection;

/*!
 @method invalidateConnection:

 @abstract Mark a connection as invalid and remove from pool.

 @discussion Use when a connection encounters an error that
 cannot be recovered from. Connection will be closed and not reused.

 @param connection The invalid connection.
 */
- (void)invalidateConnection:(sqlite3 *)connection;

#pragma mark - Pool Statistics

/*!
 @method availableConnections

 @abstract Number of connections currently available.

 @return Available connection count.
 */
- (NSUInteger)availableConnections;

/*!
 @method totalConnections

 @abstract Total connections in the pool (available + in use).

 @return Total connection count.
 */
- (NSUInteger)totalConnections;

/*!
 @method activeConnections

 @abstract Number of connections currently in use.

 @return Active connection count.
 */
- (NSUInteger)activeConnections;

/*!
 @method peakConnections

 @abstract Maximum connections reached since pool creation.

 @return Peak connection count.
 */
- (NSUInteger)peakConnections;

#pragma mark - Pool Maintenance

/*!
 @method pruneIdleConnections

 @abstract Close idle connections above minimum.

 @discussion Called automatically after idle timeout.
 Can be called manually to free resources.
 */
- (void)pruneIdleConnections;

/*!
 @method closeAllConnections

 @abstract Close all connections immediately.

 @warning Connections in use will be invalidated.
 Use only when shutting down.
 */
- (void)closeAllConnections;

#pragma mark - Configuration

/*!
 @property idleTimeout

 @abstract Seconds before idle connections above min are closed.

 Default: 60 seconds.
 */
@property (nonatomic, assign) NSTimeInterval idleTimeout;

/*!
 @property maxConnections

 @abstract Maximum connections allowed.

 Read-only after initialization.
 */
@property (nonatomic, readonly) NSUInteger maxConnections;

/*!
 @property minConnections

 @abstract Minimum connections to maintain.

 Read-only after initialization.
 */
@property (nonatomic, readonly) NSUInteger minConnections;

/*!
 @property databasePath

 @abstract Path to the database file.

 Read-only after initialization.
 */
@property (nonatomic, readonly, copy) NSString *databasePath;

#pragma mark - SQLite Configuration

/*!
 @property busyTimeout

 @abstract SQLite busy timeout in milliseconds.

 Default: 5000ms.
 */
@property (nonatomic, assign) NSUInteger busyTimeout;

/*!
 @property journalMode

 @abstract SQLite journal mode (WAL, DELETE, etc).

 Default: WAL for performance.
 */
@property (nonatomic, copy) NSString *journalMode;

/*!
 @property synchronousMode

 @abstract SQLite synchronous mode (OFF, NORMAL, FULL).

 Default: NORMAL for balance of safety/performance.
 */
@property (nonatomic, copy) NSString *synchronousMode;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>
#import <sqlite3.h>

/**
 * @abstract Supplies SQLite connections and transaction boundaries.
 */
@protocol ATProtoConnectionManager;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Creates a service-specific error for a SQLite failure.
 * @param db The active SQLite connection, or nil when connection acquisition failed.
 * @param code The SQLite or connection-manager error code.
 * @param fallback A description to use when SQLite provides no error message.
 * @return An error suitable for the caller's service boundary.
 */
typedef NSError * _Nonnull (^ATProtoDatabaseQueryRunnerErrorFactory)(sqlite3 * _Nullable db,
                                                                     NSInteger code,
                                                                     NSString *fallback);

/**
 * @abstract Executes statements on one in-flight write transaction.
 * @discussion The runner passes a transactor to @c performWriteTransaction:error:. Every operation
 * uses the transaction's connection, so reads observe earlier writes in the same transaction.
 */
@protocol ATProtoDatabaseTransactor <NSObject>

/**
 * @abstract Executes a query on the transaction's connection.
 * @param sql The SQL statement to prepare and execute.
 * @param params Positional values to bind, or nil when the statement has no parameters.
 * @param error Receives preparation, binding, or execution failures.
 * @return Rows keyed by column name, or nil when the query fails. SQL NULL values become NSNull.
 */
- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;

/**
 * @abstract Executes one write statement on the transaction's connection.
 * @param sql The INSERT, UPDATE, DELETE, or DDL statement to execute.
 * @param params Positional values to bind, or nil when the statement has no parameters.
 * @param error Receives preparation, binding, or execution failures.
 * @return YES when SQLite completes the statement, including writes that change no rows.
 */
- (BOOL)executeUpdate:(NSString *)sql
               params:(nullable NSArray *)params
                error:(NSError **)error;

@end

/**
 * @abstract The public surface of @c ATProtoDatabaseQueryRunner, extracted as a protocol
 * so callers outside Storage (e.g. Transport's @c ATProtoRateLimiter) can depend on the
 * capability without linking the concrete class.
 */
@protocol ATProtoQueryRunning <NSObject>

/**
 * @abstract Executes a query on a connection supplied by the manager.
 * @param sql The SQL statement to prepare and execute.
 * @param params Positional values to bind, or nil when the statement has no parameters.
 * @param error Receives connection, preparation, binding, or execution failures.
 * @return Rows keyed by column name, or nil when the query fails. SQL NULL values become NSNull.
 */
- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;

/**
 * @abstract Executes one write statement on a connection supplied by the manager.
 * @param sql The INSERT, UPDATE, DELETE, or DDL statement to execute.
 * @param params Positional values to bind, or nil when the statement has no parameters.
 * @param error Receives connection, preparation, binding, or execution failures.
 * @return The number of changed rows, or -1 on failure. A successful no-op returns 0.
 */
- (NSInteger)executeUpdate:(NSString *)sql
                    params:(nullable NSArray *)params
                     error:(NSError **)error;

/**
 * @abstract Runs a block inside a manager-controlled write transaction.
 * @param block Work that uses the transaction-bound transactor. Return NO to roll back.
 * @param error Receives the block's error or a translated transaction failure.
 * @return YES when the transaction commits; otherwise NO.
 */
- (BOOL)performWriteTransaction:(BOOL (^)(id<ATProtoDatabaseTransactor> tx, NSError **error))block
                          error:(NSError **)error;

@end

/**
 * @abstract Executes parameterized SQLite statements through a connection manager.
 * @discussion Each non-transactional call acquires its connection from the supplied manager.
 * Transaction blocks receive an @c ATProtoDatabaseTransactor bound to one write transaction.
 */
@interface ATProtoDatabaseQueryRunner : NSObject <ATProtoQueryRunning>

/**
 * @abstract Unavailable; initialize the runner with a connection manager.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Creates a runner that reports failures in the supplied error domain.
 * @param connectionManager The manager that supplies connections and write transactions.
 * @param errorDomain The domain assigned to query-runner errors.
 * @return An initialized query runner.
 */
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              errorDomain:(NSString *)errorDomain;

/**
 * @abstract Creates a runner with custom error translation.
 * @param connectionManager The manager that supplies connections and write transactions.
 * @param errorFactory The factory used to translate SQLite and manager failures.
 * @return An initialized query runner.
 */
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                             errorFactory:(ATProtoDatabaseQueryRunnerErrorFactory)errorFactory NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Executes a query on a connection supplied by the manager.
 * @param sql The SQL statement to prepare and execute.
 * @param params Positional values to bind, or nil when the statement has no parameters.
 * @param error Receives connection, preparation, binding, or execution failures.
 * @return Rows keyed by column name, or nil when the query fails. SQL NULL values become NSNull.
 */
- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;

/**
 * @abstract Executes one write statement on a connection supplied by the manager.
 * @param sql The INSERT, UPDATE, DELETE, or DDL statement to execute.
 * @param params Positional values to bind, or nil when the statement has no parameters.
 * @param error Receives connection, preparation, binding, or execution failures.
 * @return The number of changed rows, or -1 on failure. A successful no-op returns 0.
 */
- (NSInteger)executeUpdate:(NSString *)sql
                    params:(nullable NSArray *)params
                     error:(NSError **)error;

/**
 * @abstract Runs a block inside a manager-controlled write transaction.
 * @param block Work that uses the transaction-bound transactor. Return NO to roll back.
 * @param error Receives the block's error or a translated transaction failure.
 * @return YES when the transaction commits; otherwise NO.
 */
- (BOOL)performWriteTransaction:(BOOL (^)(id<ATProtoDatabaseTransactor> tx, NSError **error))block
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

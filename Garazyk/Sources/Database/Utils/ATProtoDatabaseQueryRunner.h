// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>
#import <sqlite3.h>

@protocol ATProtoConnectionManager;

NS_ASSUME_NONNULL_BEGIN

typedef NSError * _Nonnull (^ATProtoDatabaseQueryRunnerErrorFactory)(sqlite3 * _Nullable db,
                                                                     NSInteger code,
                                                                     NSString *fallback);

/// A database handle scoped to a single in-flight write transaction — the object handed to a
/// @c -performWriteTransaction: block. It exposes the same read/write verbs as the runner but
/// bound to the transaction's connection, so the block never touches a raw @c sqlite3 *.
/// Mirrors the Reader / Transactor role split of @c PDSActorStore.
@protocol ATProtoDatabaseTransactor <NSObject>

/// Runs a query within the transaction; same row shape as the runner's
/// @c executeQuery:params:error:.
- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;

/// Runs a single write within the transaction. Returns @c YES on success; on failure returns
/// @c NO and populates @c error — which the block should propagate to roll the transaction back.
- (BOOL)executeUpdate:(NSString *)sql
               params:(nullable NSArray *)params
                error:(NSError **)error;

@end

@interface ATProtoDatabaseQueryRunner : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              errorDomain:(NSString *)errorDomain;
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                             errorFactory:(ATProtoDatabaseQueryRunnerErrorFactory)errorFactory NS_DESIGNATED_INITIALIZER;

- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;

/// Executes a single write statement (INSERT/UPDATE/DELETE/DDL) on a self-managed
/// connection, mirroring @c executeQuery:params:error: for the write side.
/// @return The number of rows changed (>= 0), or a negative value on failure (with
///         @c error populated). A statement that succeeds but matches no rows returns 0.
- (NSInteger)executeUpdate:(NSString *)sql
                    params:(nullable NSArray *)params
                     error:(NSError **)error;

/// Runs @c block inside a write transaction (BEGIN … COMMIT/ROLLBACK). The block receives a
/// transactor bound to the transaction's connection; returning @c NO (or leaving @c *error set)
/// rolls the transaction back. No raw @c sqlite3 * is exposed to the block.
- (BOOL)performWriteTransaction:(BOOL (^)(id<ATProtoDatabaseTransactor> tx, NSError **error))block
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

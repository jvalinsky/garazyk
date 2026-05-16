// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file DatabasePool.h

 @abstract Connection pool for per-user SQLite databases.

 @discussion Manages a pool of PDSActorStore instances for efficient access
 to user-specific databases. Handles opening, caching, and eviction of
 database connections based on usage patterns.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSActorStore;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlock;
/**
 * @abstract Reads actor-scoped repository data.
 */
@protocol PDSActorStoreReader;
@protocol PDSActorStoreTransactor;

/*! Error domain for database pool errors. */
extern NSString * const PDSDatabasePoolErrorDomain;

/*!

 @abstract Error codes for pool operations.

 @constant PDSDatabasePoolErrorStoreNotFound Actor store not found.
 @constant PDSDatabasePoolErrorStoreClosed Store was closed unexpectedly.
 @constant PDSDatabasePoolErrorTransactionFailed Transaction failed.
 */
typedef NS_ENUM(NSInteger, PDSDatabasePoolError) {
    PDSDatabasePoolErrorStoreNotFound = 1000,
    PDSDatabasePoolErrorStoreClosed,
    PDSDatabasePoolErrorTransactionFailed,
};

/*!
 @class PDSDatabasePool

 @abstract Pool of per-user database connections.

 @discussion Caches actor store connections with LRU eviction.
 */
@interface PDSDatabasePool : NSObject

/*! Directory containing database files. */
@property (nonatomic, copy, readonly) NSString *dbDirectory;

/*! Maximum number of cached stores. */
@property (nonatomic, assign, readonly) NSUInteger maxSize;

/*! Current number of cached stores. */
@property (nonatomic, assign, readonly) NSUInteger currentSize;

/*! Number of open file handles. */
@property (nonatomic, assign, readonly) NSUInteger openFileHandleCount;

/*! Master secret for database encryption/decryption. */
@property (nonatomic, copy, nullable) NSString *masterSecret;

- (instancetype)initWithDbDirectory:(NSString *)dbDirectory maxSize:(NSUInteger)maxSize;

/*! Gets or creates an actor store for a DID. */
- (nullable PDSActorStore *)storeForDid:(NSString *)did error:(NSError **)error;

/*! Executes a write transaction for a DID. */
- (void)transactWithDid:(NSString *)did 
                  block:(void (^)(id<PDSActorStoreTransactor> transactor, NSError **error))block 
                  error:(NSError **)error;

/*! Executes a read-only transaction for a DID. */
- (void)readWithDid:(NSString *)did 
               block:(void (^)(id<PDSActorStoreReader> reader, NSError **error))block 
               error:(NSError **)error;

/*! Gets an account by DID. */
- (nullable PDSDatabaseAccount *)getAccount:(NSString *)did error:(NSError **)error;

/*! Gets a repo by DID. */
- (nullable PDSDatabaseRepo *)getRepo:(NSString *)did error:(NSError **)error;

/*! Gets a repo root CID by DID. */
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;

/*! Gets a record by URI for a DID. */
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;

/*! Gets all accounts. */
- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;

/*! Gets all repos. */
- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error;

/*! Evicts unused stores from the cache. */
- (void)evictUnusedStores;

/*! Evicts a specific store from the cache. */
- (void)evictStoreForDid:(NSString *)did;

/*! Closes all cached stores. */
- (void)closeAll;

/*! Collects pool metrics. */
- (NSDictionary<NSString *, id> *)collectMetrics;

@end

NS_ASSUME_NONNULL_END

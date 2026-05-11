// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSActorStoreInternal.h
 @abstract Internal interface for PDSActorStore categories.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "ActorStore.h"
#import <sqlite3.h>
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSBiometricKeychain;

@interface PDSActorStore ()

@property (nonatomic, copy, readwrite) NSString *did;
@property (nonatomic, copy, readwrite) NSString *dbPath;
@property (nonatomic, assign, readwrite, nullable) sqlite3 *db;
@property (nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, strong) NSMapTable<NSString *, NSValue *> *stmtCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *blobCache;

#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t transactionQueue;
#else
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t transactionQueue;
#endif

- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;
- (void)finalizeStatement:(sqlite3_stmt *)stmt;
- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt;
- (NSError *)errorWithSQLiteResult:(int)result message:(NSString *)message;

- (BOOL)generateSigningKeyForDid:(NSString *)did error:(NSError **)error;
- (BOOL)generateSigningKeyWithError:(NSError **)error;

@end

extern const void * const kPDSActorStoreQueueKey;

NS_ASSUME_NONNULL_END

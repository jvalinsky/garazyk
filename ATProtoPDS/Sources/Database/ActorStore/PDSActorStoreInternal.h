/*!
 @file PDSActorStoreInternal.h
 @abstract Internal interface for PDSActorStore categories.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "ActorStore.h"
#import "Compat/PDSTypes.h"

#if !defined(GNUSTEP)
#import <Security/Security.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class PDSBiometricKeychain;

@interface PDSActorStore ()

@property (nonatomic, copy, readwrite) NSString *did;
@property (nonatomic, copy, readwrite) NSString *dbPath;
@property (nonatomic, assign, readwrite) sqlite3 *db;
@property (nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property (nonatomic, strong) NSMapTable<NSString *, NSValue *> *stmtCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *blobCache;
@property (nonatomic, assign, readwrite) BOOL keychainNeedsUpgrade;

#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t transactionQueue;
@property (nonatomic, strong) NSData *signingKeyData;
#else
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t transactionQueue;
/* signingKey uses 'assign' (not 'strong') for Core Foundation compatibility.
   The setter releases any existing key before assigning a new one.
   Keys are released in -close. Do not release keys assigned to this property. */
@property (nonatomic, assign) SecKeyRef signingKey;
@property (nonatomic, strong) PDSBiometricKeychain *biometricKeychain;
#endif

- (sqlite3_stmt *)prepareStatement:(NSString *)sql error:(NSError **)error;
- (void)finalizeStatement:(sqlite3_stmt *)stmt;
- (PDSDatabaseAccount *)accountFromStatement:(sqlite3_stmt *)stmt;
- (NSError *)errorWithSQLiteResult:(int)result message:(NSString *)message;

#if defined(GNUSTEP)
- (BOOL)generateSigningKeyForDid:(NSString *)did error:(NSError **)error;
#else
- (BOOL)generateSigningKeyWithError:(NSError **)error;
#endif

@end

NS_ASSUME_NONNULL_END

/*!
 @file ServiceDatabases.h

 @abstract Shared service-level database operations.

 @discussion Provides unified access to service databases including accounts,
 refresh tokens, invite codes, DID cache, and sequencer. Coordinates between
 multiple database pools for different data types.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSAccountRepository.h"
#import "Core/Repositories/PDSSessionRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;
@class PDSDatabase;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseBlob;
@class PDSDatabaseRecord;

/*! Error domain for service database operations. */
extern NSString * const PDSServiceDatabasesErrorDomain;

/*!
 @class PDSServiceDatabases

 @abstract Manages shared service-level databases for the PDS.

 @discussion PDSServiceDatabases provides a unified interface for accessing
 service-level data across multiple database pools:

 - **Service Pool**: Accounts, refresh tokens, invite codes, JWT keys
 - **DID Cache Pool**: Cached DID documents with expiration
 - **Sequencer Pool**: Repository event sequencing

 The class coordinates database pool lifecycle and provides high-level
 methods for common operations like account management and DID resolution.

 Thread-safety: Methods are thread-safe through pool-level serialization.

 Usage:
 @code
 PDSServiceDatabases *dbs = [PDSServiceDatabases sharedInstance];
 PDSDatabaseAccount *account = [dbs getAccountByDid:@"did:plc:..." error:nil];
 @endcode
 */
@interface PDSServiceDatabases : NSObject <PDSAccountRepository, PDSSessionRepository>

/*! Pool for service database (accounts, tokens, invite codes). */
@property (nonatomic, strong, readonly) PDSDatabasePool *servicePool;

/*! Pool for DID document cache. */
@property (nonatomic, strong, readonly) PDSDatabasePool *didCachePool;

/*! Pool for repository event sequencer. */
@property (nonatomic, strong, readonly) PDSDatabasePool *sequencerPool;

/*! Pool for user-level databases. */
@property (nonatomic, strong, readonly) PDSDatabasePool *userDatabasePool;

/*! Policy value for refresh token expiry (seconds). Defaults to 30 days. */
@property (nonatomic, assign) NSUInteger refreshTokenTTLSeconds;

/*!
 @method sharedInstance

 @abstract Get singleton service databases instance.

 @discussion Returns a shared instance configured with default pool sizes.
 For custom configuration, use initWithDirectory:serviceMaxSize:didCacheMaxSize:sequencerMaxSize:.

 @return Shared PDSServiceDatabases instance.
 */
+ (instancetype)sharedInstance;

/*!
 @method serviceDatabaseWithError:
 
 @abstract Get service database connection from pool.
 
 @param error Error pointer for connection failures.
 @return PDSDatabase instance or nil on failure.
 */
- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error;

/*!
 @method serviceDatabase
 
 @abstract Get raw service database connection from pool.
 
 @return Raw sqlite3 handle or NULL on failure.
 */
- (nullable sqlite3 *)serviceDatabase;

/*!
 @method initWithDirectory:serviceMaxSize:didCacheMaxSize:sequencerMaxSize:

 @abstract Initialize with custom pool configuration.

 @param directory Base directory for database files.
 @param serviceMaxSize Maximum connections for service pool.
 @param didCacheMaxSize Maximum connections for DID cache pool.
 @param sequencerMaxSize Maximum connections for sequencer pool.
 @return Initialized service databases instance.
 */
- (instancetype)initWithDirectory:(NSString *)directory
                     serviceMaxSize:(NSUInteger)serviceMaxSize
                   didCacheMaxSize:(NSUInteger)didCacheMaxSize
                 sequencerMaxSize:(NSUInteger)sequencerMaxSize;

#pragma mark - Account Management

/*!
 @method createAccount:error:

 @abstract Create a new account in service database.

 @param account Account object with DID, handle, email, password hash.
 @param error Error pointer for creation failures.
 @return YES if created successfully, NO on failure.
 */
- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)createAccounts:(NSArray<PDSDatabaseAccount *> *)accounts error:(NSError **)error;
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error;
- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByEmail:(NSString *)email error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error;
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;
- (nullable NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;
- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;
- (nullable NSArray<PDSDatabaseAccount *> *)getAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;

#pragma mark - Refresh Tokens

/*!
 @method storeRefreshToken:forAccount:error:

 @abstract Store a refresh token for an account.

 @param token Refresh token string.
 @param accountDid DID of account that owns the token.
 @param error Error pointer for storage failures.
 @return YES if stored successfully, NO on failure.
 */
- (BOOL)storeRefreshToken:(NSString *)token forAccountDid:(NSString *)accountDid error:(NSError **)error;
- (BOOL)storeRefreshToken:(NSString *)token forAccount:(NSString *)accountDid error:(NSError **)error;
- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error;
- (BOOL)revokeRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)deleteRefreshToken:(NSString *)token error:(NSError **)error;
- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)accountDid error:(NSError **)error;
- (BOOL)deleteRefreshTokensForAccount:(NSString *)accountDid error:(NSError **)error;

#pragma mark - Invite Codes

/*!
 @method createInviteCode:forAccount:maxUses:error:

 @abstract Create an invite code for account creation.

 @param code Invite code string (unique).
 @param accountDid DID of account that generated the code.
 @param maxUses Maximum number of times code can be used.
 @param error Error pointer for creation failures.
 @return YES if created successfully, NO on failure.
 */
- (BOOL)createInviteCode:(NSString *)code
              forAccount:(NSString *)accountDid
              maxUses:(NSInteger)maxUses
                 error:(NSError **)error;

/*!
 @method getInviteCodeForAccount:error:

 @abstract Retrieve invite code generated by an account.

 @param accountDid DID of account that generated the code.
 @param error Error pointer for retrieval failures.
 @return Invite code string or nil if not found.
 */
- (nullable NSString *)getInviteCodeForAccount:(NSString *)accountDid error:(NSError **)error;

/*!
 @method useInviteCode:error:

 @abstract Consume one use of an invite code.

 @discussion Increments use count. Returns NO if code doesn't exist or
 has reached max uses.

 @param code Invite code to consume.
 @param error Error pointer for validation failures.
 @return YES if code valid and use recorded, NO if invalid or exhausted.
 */
- (BOOL)useInviteCode:(NSString *)code error:(NSError **)error;

#pragma mark - Reserved Handles

/*!
 @method reserveHandle:error:

 @abstract Persist a normalized reserved handle.

 @param handle Normalized handle string to reserve.
 @param error Error pointer for persistence failures.
 @return YES if reserved or already reserved, NO on failure.
 */
- (BOOL)reserveHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method isHandleReserved:error:

 @abstract Check whether a normalized handle is reserved.

 @param handle Normalized handle string.
 @param error Error pointer for query failures.
 @return YES when handle exists in reserved_handles table, otherwise NO.
 */
- (BOOL)isHandleReserved:(NSString *)handle error:(NSError **)error;

#pragma mark - App Passwords

/*!
 @method createAppPasswordForAccount:name:privileged:error:

 @abstract Create an app password for an account.

 @param accountDid Account DID that owns the app password.
 @param name Human-friendly name of the app password.
 @param privileged Whether the app password is privileged.
 @param error Error pointer for creation failures.
 @return Dictionary matching com.atproto.server.createAppPassword output (includes password).
 */
- (nullable NSDictionary *)createAppPasswordForAccount:(NSString *)accountDid
                                                 name:(NSString *)name
                                           privileged:(BOOL)privileged
                                                error:(NSError **)error;

/*!
 @method listAppPasswordsForAccount:error:

 @abstract List existing app passwords for an account (excluding secret password).

 @param accountDid Account DID.
 @param error Error pointer for retrieval failures.
 @return Array of dictionaries matching com.atproto.server.listAppPasswords schema.
 */
- (NSArray<NSDictionary *> *)listAppPasswordsForAccount:(NSString *)accountDid
                                                 error:(NSError **)error;

/*!
 @method revokeAppPasswordForAccount:name:error:

 @abstract Revoke an app password by name for an account.

 @param accountDid Account DID.
 @param name App password name.
 @param error Error pointer for revocation failures.
 @return YES if revoked, NO on failure or not found.
 */
- (BOOL)revokeAppPasswordForAccount:(NSString *)accountDid
                               name:(NSString *)name
                              error:(NSError **)error;

/*!
 @method verifyAppPasswordForAccount:password:error:

 @abstract Verify an app password string for an account.

 @param accountDid Account DID.
 @param password Candidate app password string.
 @param error Error pointer for verification failures.
 @return YES if password matches an active app password.
 */
- (BOOL)verifyAppPasswordForAccount:(NSString *)accountDid
                           password:(NSString *)password
                              error:(NSError **)error;

#pragma mark - DID Cache

/*!
 @method cacheDID:document:expiresAt:

 @abstract Cache a DID document with expiration.

 @param did Decentralized identifier.
 @param document DID document as JSON dictionary.
 @param expiresAt Expiration date for cache entry.
 */
- (void)cacheDID:(NSString *)did
        document:(NSDictionary *)document
      expiresAt:(NSDate *)expiresAt;

/*!
 @method resolveDID:

 @abstract Resolve DID from cache if not expired.

 @param did Decentralized identifier to resolve.
 @return Cached DID document dictionary, or nil if not cached or expired.
 */
- (nullable NSDictionary *)resolveDID:(NSString *)did;

#pragma mark - Event Persistence

/*!
 @method logHostingEvent:type:details:createdBy:error:

 @abstract Log a hosting event (account creation, handle update, etc.).

 @param did The DID of the account.
 @param type The type of event (e.g. account_created, handle_updated).
 @param details Optional dictionary of event details (will be JSON serialized).
 @param createdBy Optional DID of the actor creating the event.
 @param error Error pointer.
 @return YES if logged successfully.
 */
- (BOOL)logHostingEvent:(NSString *)did
                   type:(NSString *)type
                details:(nullable NSDictionary *)details
              createdBy:(nullable NSString *)createdBy
                  error:(NSError **)error;

/*!
 @method persistEvent:seq:type:data:error:

 @abstract Store a firehose event.

 @param seq Global sequence number.
 @param type Event type (e.g. #commit, #identity).
 @param data CBOR encoded event data.
 @param error Error pointer.
 @return YES if stored successfully.
 */
- (BOOL)persistEvent:(int64_t)seq
                type:(NSString *)type
                data:(NSData *)data
               error:(NSError **)error;

/*!
 @method getEventsSince:limit:error:

 @abstract Retrieve events for playback.

 @param seq Cursor (exclusive).
 @param limit Maximum number of events to return.
 @param error Error pointer.
 @return Array of dictionaries containing event data (keys: seq, type, data, created_at).
 */
- (nullable NSArray<NSDictionary *> *)getEventsSince:(int64_t)seq
                                              limit:(NSInteger)limit
                                              error:(NSError **)error;

/*!
 @method getMaxEventSequence:

 @abstract Get the highest sequence number in the events table.

 @param error Error pointer.
 @return Max sequence number, or 0 if empty/error.
 */
- (int64_t)getMaxEventSequence:(NSError **)error;

/*!
 @method pruneEventsBefore:error:

 @abstract Delete events created before the specified date.

 @param date Cutoff date. Events older than this will be deleted.
 @param error Error pointer.
 @return YES if operation successful (even if 0 deleted).
 */
- (BOOL)pruneEventsBefore:(NSDate *)date error:(NSError **)error;

#pragma mark - Lifecycle

/*!
 @method closeAll

 @abstract Close all database pools.

 @discussion Closes service, DID cache, and sequencer pools. Call during
 shutdown to release resources.
 */
- (void)closeAll;

@end

NS_ASSUME_NONNULL_END

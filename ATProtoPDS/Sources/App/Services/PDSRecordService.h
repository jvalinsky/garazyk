/*!
 @file PDSRecordService.h

 @abstract Record management service layer.

 @discussion Provides CRUD operations for ATProto records within repositories.
 Handles record listing with pagination and repository statistics.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for PDSRecordService errors. */
extern NSErrorDomain const PDSRecordServiceErrorDomain;

/*! Error codes for PDSRecordService. */
typedef NS_ENUM(NSInteger, PDSRecordServiceError) {
    PDSRecordServiceErrorUnauthorized = 1,
};

/*! Posted when a record is written (put or delete). userInfo keys: did, collection, rkey, action ("create"/"delete"). */
extern NSNotificationName const PDSRecordDidChangeNotification;

@class PDSDatabasePool;
@class ATProtoLexiconValidator;

/*! Validation mode for record operations. */
typedef NS_ENUM(NSInteger, PDSValidationMode) {
    PDSValidationModeRequired,   /*! Fail if lexicon unknown or validation fails. */
    PDSValidationModeOptimistic, /*! Validate if known, allow if unknown. */
    PDSValidationModeOff         /*! Skip validation. */
};

/*!
 @class PDSRecordService

 @abstract Service for record management operations.
 */
@interface PDSRecordService : NSObject

/*! Database pool - owner (PDSController) must outlive this service. */
@property (nonatomic, strong) PDSDatabasePool *databasePool;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Record Operations

/*! Gets a record by AT URI. */
- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;

/*! Lists records in a collection with pagination. */
- (nullable NSArray *)listRecords:(NSString *)collection
                          forDid:(NSString *)did
                           limit:(NSUInteger)limit
                          cursor:(nullable NSString *)cursor
                          error:(NSError **)error;

/*! Creates or updates a record.
    @param collection The collection NSID (e.g., "app.bsky.feed.post").
    @param rkey The record key within the collection.
    @param value The record value as a dictionary.
    @param did The repository owner DID.
    @param actorDid The authenticated actor's DID (for authorization). Must equal did for self-modification.
    @param mode Validation mode.
    @param error On failure, describes what went wrong.
    @return YES on success, NO on failure. */
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
          actorDid:(NSString *)actorDid
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error;

/*! Creates or updates a record (convenience method with actorDid=did). */
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error;

/*! Creates or updates a record (convenience method with default optimistic validation and actorDid=did). */
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
             error:(NSError **)error;

/*! Deletes a record.
    @param collection The collection NSID.
    @param rkey The record key.
    @param did The repository owner DID.
    @param actorDid The authenticated actor's DID (for authorization). Must equal did for self-modification.
    @param error On failure, describes what went wrong.
    @return YES on success, NO on failure. */
- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
             actorDid:(NSString *)actorDid
                error:(NSError **)error;

/*! Deletes a record (convenience method with actorDid=did). */
- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
                error:(NSError **)error;

/*! Atomically applies a batch of writes (create/update/delete) in a single transaction.
    If any write fails, all preceding writes in the batch are rolled back.
    @param writes Array of write operations, each a dictionary with keys: action, collection, rkey (required for update/delete), and value (for create/update). Legacy key 'record' is also accepted for compatibility.
    @param did The repository DID.
    @param actorDid The authenticated actor's DID (for authorization). Must equal did for self-modification.
    @param validate Whether to apply lexicon validation.
    @param swapCommit If non-nil, the expected current repo root CID. Fails if it doesn't match.
    @param error On failure, describes what went wrong.
    @return Result dictionary with commit info on success, nil on failure. */
- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                 forDid:(NSString *)did
                               actorDid:(NSString *)actorDid
                               validate:(BOOL)validate
                             swapCommit:(nullable NSString *)swapCommit
                                  error:(NSError **)error;

/*! Atomically applies a batch of writes (convenience method with actorDid=did). */
- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                 forDid:(NSString *)did
                               validate:(BOOL)validate
                             swapCommit:(nullable NSString *)swapCommit
                                  error:(NSError **)error;

/*! Gets repository statistics (record count, blob count, etc). */
- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

/*!
 @file PDSSyncService.h
 @abstract Repository synchronization service layer.
 @discussion Implements com.atproto.sync.* operations including CAR file 
 generation, block retrieval, and repository listing. Matches the pattern 
 of other service layers in the PDS.
 
 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class PDSDatabasePool;
@class PDSRepositoryService;

/*!
 @class PDSSyncService
 @abstract Service for ATProto synchronization operations.
 */
@interface PDSSyncService : NSObject

#if defined(GNUSTEP)
@property (nonatomic, assign) PDSDatabasePool *databasePool;
#else
@property (nonatomic, weak) PDSDatabasePool *databasePool;
#endif

/*! Service-level databases for sequencer and account tracking. */
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;

/*! Repository service for block and MST access. */
@property (nonatomic, strong) PDSRepositoryService *repositoryService;

/*!
 @method initWithDatabasePool:repositoryService:
 @abstract Initializes the sync service with required dependencies.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool 
                   repositoryService:(PDSRepositoryService *)repositoryService;

#pragma mark - Sync Operations

/*! 
 @abstract Gets the full repository as a CAR file.
 @param did The repository DID.
 @param since Optional CID to start from for incremental sync.
 @param error Error pointer.
 @return CAR-encoded repository data, or nil on failure.
 */
- (nullable NSData *)getRepo:(NSString *)did since:(nullable NSString *)since error:(NSError **)error;

/*!
 @abstract Gets specific blocks from a repository.
 @param did The repository DID.
 @param cids Array of CIDs (as strings) to retrieve.
 @param error Error pointer.
 @return Array of raw block data, or nil on failure.
 */
- (nullable NSArray<NSData *> *)getBlocks:(NSString *)did cids:(NSArray<NSString *> *)cids error:(NSError **)error;

/*!
 @abstract Gets the latest commit CID and revision for a repository.
 @param did The repository DID.
 @param error Error pointer.
 @return Dictionary containing 'cid' and 'rev', or nil on failure.
 */
- (nullable NSDictionary *)getLatestCommit:(NSString *)did error:(NSError **)error;

/*!
 @abstract Lists repositories hosted on this server.
 @param limit Maximum number of repositories to return.
 @param cursor Pagination cursor.
 @param error Error pointer.
 @return Array of repository info dictionaries.
 */
- (nullable NSArray<NSDictionary *> *)listReposWithLimit:(NSUInteger)limit 
                                                 cursor:(nullable NSString *)cursor 
                                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRecordService_Internal.h

 @abstract Internal class extension and private method signatures for PDSRecordService.

 @discussion Provides the private properties and method declarations shared across
 all PDSRecordService category files. Not to be imported by external callers.
 */

#import "PDSRecordService.h"
#import "Compat/PDSTypes.h"
#import "Core/GZPerDidWriteDispatcher.h"

@class PDSActorStore;
@class PDSDatabaseBlock;
@class RepoCommit;
@class PDSDatabaseRecord;
@class PDSSQLiteRecordRepository;

@protocol PDSActorStoreTransactor;
@protocol PDSActorStoreReader;

NS_ASSUME_NONNULL_BEGIN

@interface PDSRecordService ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *statsCacheByDid;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t statsCacheQueue;
@property (nonatomic, strong) GZPerDidWriteDispatcher *writeDispatcher;

#pragma mark - Shared Private Methods

- (void)_dispatchWriteForDid:(NSString *)did block:(void (^)(void))block;

- (BOOL)checkAuthorizationForDid:(NSString *)targetDid actorDid:(NSString *)actorDid error:(NSError **)error;

- (nullable NSDictionary *)_applyWritesSerialized:(NSArray<NSDictionary *> *)writes
                                         forDid:(NSString *)did
                                       actorDid:(NSString *)actorDid
                                 validationMode:(PDSValidationMode)mode
                                     swapCommit:(nullable NSString *)swapCommit
                                          error:(NSError **)error;

- (nullable MST *)loadRepoMSTForDid:(NSString *)did
                               store:(PDSActorStore *)store
                               error:(NSError **)error;

- (nullable CID *)computeRepoRootCIDForDid:(NSString *)did
                                      store:(PDSActorStore *)store
                                      error:(NSError **)error;

- (nullable NSDictionary<NSString *, NSString *> *)refreshRepoRootMetadataForDid:(NSString *)did
                                                                    preferredRev:(nullable NSString *)preferredRev
                                                              mutationCIDsByKey:(nullable NSDictionary<NSString *, id> *)mutationCIDsByKey
                                                             mutationBlocksByCID:(nullable NSDictionary<NSString *, NSData *> *)mutationBlocksByCID
                                                                     changedKeys:(nullable NSArray<NSString *> *)changedKeys
                                                                           error:(NSError **)error;

- (nullable NSArray<PDSDatabaseBlock *> *)changedMSTBlocksForMST:(MST *)mst
                                                     changedKeys:(NSArray<NSString *> *)changedKeys
                                                            rev:(NSString *)rev
                                                          error:(NSError **)error;

- (BOOL)validateThreadgateForReplyRecord:(NSDictionary *)record
                              collection:(NSString *)collection
                               authorDID:(NSString *)authorDID
                                   error:(NSError **)error;

- (nullable NSDictionary *)threadgateRecordForPostURI:(NSString *)postURI
                                            authorDID:(NSString *)authorDID
                                                error:(NSError **)error;

- (BOOL)authorDID:(NSString *)authorDID hasFollowForDID:(NSString *)targetDID error:(NSError **)error;

- (NSString *)generateCIDForData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

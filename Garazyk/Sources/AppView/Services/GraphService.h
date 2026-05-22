// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GraphService.h

 @abstract Social graph service for follows, blocks, mutes, and relationships.

 @discussion Provides query operations for the social graph including
 followers, follows, blocks, mutes, and relationships between actors.
 Part of AppView layer for read-optimized social data access.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

/**
 * @abstract Defines the PDSQueryDatabase protocol contract.
 */
@protocol PDSQueryDatabase;

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @class GraphService
 
 @abstract Service for social graph operations.
 
 @discussion Queries follow, block, and mute records to provide paginated
 social graph views. Uses the same record/block storage pattern as FeedService.
 */
@interface GraphService : NSObject

/*! Initialize with database connection. */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) id<PDSQueryDatabase> database;


#pragma mark - Follows

/*! Get actors that the given actor follows. */
- (nullable NSDictionary *)getFollowsForActor:(NSString *)actorDID
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

/*! Get actors that follow the given actor. */
- (nullable NSDictionary *)getFollowersForActor:(NSString *)actorDID
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error;

#pragma mark - Blocks

/*! Get actors blocked by the given actor. */
- (nullable NSDictionary *)getBlocksForActor:(NSString *)actorDID
                                        limit:(NSInteger)limit
                                       cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

#pragma mark - Mutes

/*! Mute an actor. */
- (BOOL)muteActor:(NSString *)targetDID forActor:(NSString *)actorDID error:(NSError **)error;

/*! Unmute an actor. */
- (BOOL)unmuteActor:(NSString *)targetDID forActor:(NSString *)actorDID error:(NSError **)error;

/*! Get actors muted by the given actor. */
- (nullable NSDictionary *)getMutesForActor:(NSString *)actorDID
                                       limit:(NSInteger)limit
                                      cursor:(nullable NSString *)cursor
                                       error:(NSError **)error;

#pragma mark - Relationships

/*! Get relationship between viewer and target (following, followedBy, blocking, muting). */
- (nullable NSDictionary *)getRelationship:(NSString *)viewerDID
                                  withActor:(NSString *)targetDID
                                      error:(NSError **)error;

#pragma mark - Likes & Reposts (feed-adjacent graph queries)

/*! Get actors who liked a given post. */
- (nullable NSDictionary *)getLikesForURI:(NSString *)uri
                                     limit:(NSInteger)limit
                                    cursor:(nullable NSString *)cursor
                                     error:(NSError **)error;

/*! Get actors who reposted a given post. */
- (nullable NSDictionary *)getRepostedByForURI:(NSString *)uri
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error;

#pragma mark - Starter Packs

/*! Get details for a specific starter pack. */
- (nullable NSDictionary *)getStarterPack:(NSString *)starterPackURI error:(NSError **)error;

/*! Get views for a list of starter packs. */
- (nullable NSArray<NSDictionary *> *)getStarterPacks:(NSArray<NSString *> *)uris error:(NSError **)error;

/*! Get starter packs created by an actor. */
- (nullable NSDictionary *)getStarterPacksForActor:(NSString *)actorDID
                                             limit:(NSInteger)limit
                                            cursor:(nullable NSString *)cursor
                                             error:(NSError **)error;

/*! Search starter packs by name. */
- (nullable NSDictionary *)searchStarterPacks:(NSString *)query
                                        limit:(NSInteger)limit
                                       cursor:(nullable NSString *)cursor
                                        error:(NSError **)error;

/*! Index a starter pack record. */
- (BOOL)indexStarterPack:(NSDictionary *)record
                     did:(NSString *)did
                    rkey:(NSString *)rkey
                     cid:(NSString *)cid
                   error:(NSError **)error;

/*! Unindex a starter pack record. */
- (BOOL)unindexStarterPackWithRKey:(NSString *)rkey
                               did:(NSString *)did
                             error:(NSError **)error;

#pragma mark - Lists

/*! Get lists created by an actor. */
- (nullable NSDictionary *)getListsForActor:(NSString *)actorDID
                                      limit:(NSInteger)limit
                                     cursor:(nullable NSString *)cursor
                                      error:(NSError **)error;

/*! Get a specific list with its items. */
- (nullable NSDictionary *)getList:(NSString *)listURI
                             limit:(NSInteger)limit
                            cursor:(nullable NSString *)cursor
                             error:(NSError **)error;

#pragma mark - Indexing

/**
 * @abstract Indexes a new list record in the search and query views.
 * @param record The list record payload.
 * @param did The actor DID who owns the list.
 * @param uri The AT Protocol URI of the list.
 * @param cid The CID of the list record.
 * @param error Receives details when indexing fails.
 * @return YES if indexing succeeds; otherwise NO.
 */
- (BOOL)indexList:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error;

/**
 * @abstract Removes a list record from the indexing database.
 * @param uri The AT Protocol URI of the list to unindex.
 * @param error Receives details when unindexing fails.
 * @return YES if unindexing succeeds; otherwise NO.
 */
- (BOOL)unindexListWithURI:(NSString *)uri error:(NSError **)error;

/**
 * @abstract Indexes a new list item record representing a member of a list.
 * @param record The list item record payload.
 * @param did The actor DID who added the item.
 * @param uri The AT Protocol URI of the list item record.
 * @param cid The CID of the list item record.
 * @param error Receives details when indexing fails.
 * @return YES if indexing succeeds; otherwise NO.
 */
- (BOOL)indexListitem:(NSDictionary *)record did:(NSString *)did uri:(NSString *)uri cid:(NSString *)cid error:(NSError **)error;
/**
 * @abstract Performs the unindexListitemWithURI operation.
 */
- (BOOL)unindexListitemWithURI:(NSString *)uri error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

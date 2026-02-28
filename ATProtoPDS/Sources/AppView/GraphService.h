/*!
 @file GraphService.h

 @abstract Social graph service for follows, blocks, mutes, and relationships.

 @discussion Provides query operations for the social graph including
 followers, follows, blocks, mutes, and relationships between actors.
 Part of AppView layer for read-optimized social data access.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

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
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) PDSDatabase *database;

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

/*! Get starter packs created by an actor. */
- (nullable NSDictionary *)getStarterPacksForActor:(NSString *)actorDID
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

@end

NS_ASSUME_NONNULL_END

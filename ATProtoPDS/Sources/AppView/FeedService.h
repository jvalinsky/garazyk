/*!
 @file FeedService.h

 @abstract Feed generation and post thread service.

 @discussion Provides feed views including timelines, author feeds, post threads,
 and likes. Part of AppView layer for read-optimized content access with pagination.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @class FeedService

 @abstract Service for feed generation and post threads.

 @discussion Generates various feed views with cursor-based pagination.
 Supports timelines, author feeds, post threads, custom feeds, and likes.
 */
@interface FeedService : NSObject

/*! Initialize with database connection. */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) PDSDatabase *database;

/*! Get timeline feed for actor with pagination. */
- (nullable NSDictionary *)getTimelineForActor:(NSString *)actorDID
                                          limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                          error:(NSError **)error;

/*! Get author feed for actor with optional filter and pagination. */
- (nullable NSDictionary *)getAuthorFeedForActor:(NSString *)actorDID
                                            limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                 filter:(nullable NSString *)filter
                                          error:(NSError **)error;

/*! Get post thread with replies up to specified depth. */
- (nullable NSDictionary *)getPostThread:(NSString *)uri depth:(NSInteger)depth error:(NSError **)error;

/*! Get custom feed from feed generator with pagination. */
- (nullable NSDictionary *)getFeed:(NSString *)feedGeneratorURI
                              limit:(NSInteger)limit
                            cursor:(nullable NSString *)cursor
                              error:(NSError **)error;

/*! Get posts liked by actor with pagination. */
- (nullable NSDictionary *)getActorLikes:(NSString *)actorDID
                                    limit:(NSInteger)limit
                                  cursor:(nullable NSString *)cursor
                                    error:(NSError **)error;

/*! Get multiple posts by URI. */
- (nullable NSDictionary *)getPosts:(NSArray<NSString *> *)uris error:(NSError **)error;

/*! Get a single post record by AT URI. */
- (nullable NSDictionary *)getPostByURI:(NSString *)uri error:(NSError **)error;

/*! Format a post record into an AppView post structure. */
- (nullable NSDictionary *)formatPostRecord:(NSString *)uri cid:(NSString *)cid record:(NSDictionary *)record;

/*! Generate a CID string for a record dictionary. */
- (NSString *)generateCIDForRecord:(NSDictionary *)record;

@end

NS_ASSUME_NONNULL_END

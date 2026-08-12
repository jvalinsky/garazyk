// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSActorService.h

 @abstract Actor profile and preferences service.

 @discussion Provides access to actor profiles and user preferences. Part of
 AppView layer for read-optimized data access.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @class PDSActorService
 
 @abstract Service for actor profiles and preferences.
 
 @discussion Retrieves actor profile data and manages user preferences.
 Profiles include display name, avatar, description. Preferences store
 user-specific settings.
 */
@interface PDSActorService : NSObject

/*! Initialize with database connection. */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) id<PDSQueryDatabase> database;


/*! Get profile for actor DID. */
- (nullable NSDictionary *)getProfileForActor:(NSString *)actorDID error:(NSError **)error;

/*! Get profiles for multiple actors. */
- (nullable NSArray<NSDictionary *> *)getProfilesForActors:(NSArray<NSString *> *)actorDIDs error:(NSError **)error;

/*!
 @method getProfilesByDIDForActors:error:
 @abstract Batch-hydrates profiles for a list of actor DIDs in a bounded
 number of queries and returns them keyed by DID, for callers that need to
 look a row's profile up by DID rather than by input position (e.g. inside a
 loop over rows from an unrelated table). DIDs with no profile are simply
 absent from the result, matching -getProfileForActor:error: returning nil.
 */
- (nullable NSDictionary<NSString *, NSDictionary *> *)getProfilesByDIDForActors:(NSArray<NSString *> *)actorDIDs
                                                                            error:(NSError **)error;

/*! Get followers count. */
- (NSInteger)getFollowersCountForDID:(NSString *)did error:(NSError **)error;

/*! Get follows count. */
- (NSInteger)getFollowsCountForDID:(NSString *)did error:(NSError **)error;

/*! Get posts count. */
- (NSInteger)getPostsCountForDID:(NSString *)did error:(NSError **)error;

/*! Get preferences for actor. */
- (nullable NSDictionary *)getPreferencesForActor:(NSString *)actorDID error:(NSError **)error;

/*! Update preferences for actor. */
- (BOOL)putPreferencesForActor:(NSString *)actorDID preferences:(NSArray *)preferences error:(NSError **)error;

/*! Search actors by term with pagination. */
- (nullable NSDictionary *)searchActors:(NSString *)term
                                   limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                   error:(NSError **)error;

/*! Typeahead search for actors with limit. */
- (nullable NSArray<NSDictionary *> *)searchActorsTypeahead:(NSString *)term
                                                       limit:(NSInteger)limit
                                                       error:(NSError **)error;

/*! Get total record count for a collection across all repos. */
- (NSInteger)getTotalRecordsCountForCollection:(NSString *)collection
                                    error:(NSError **)error;

/*! Get total posts count. */
- (NSInteger)getTotalPostsCount:(NSError **)error;

/*! Get total profiles count. */
- (NSInteger)getTotalProfilesCount:(NSError **)error;

/*! Get total follows count. */
- (NSInteger)getTotalFollowsCount:(NSError **)error;

/*! Resolve handle to DID. Returns DID if handle exists, nil otherwise. */
- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error;

/*! Resolve DID to handle. Returns handle if known, nil otherwise. */
- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error;

/*! Get suggested actors for the given actor. Returns follows-of-follows and popular actors. */
- (nullable NSDictionary *)getSuggestionsForActor:(NSString *)actorDID
                                            limit:(NSInteger)limit
                                           cursor:(nullable NSString *)cursor
                                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

/*!
 @file ActorService.h

 @abstract Actor profile and preferences service.

 @discussion Provides access to actor profiles and user preferences. Part of
 AppView layer for read-optimized data access.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @class ActorService

 @abstract Service for actor profiles and preferences.

 @discussion Retrieves actor profile data and manages user preferences.
 Profiles include display name, avatar, description. Preferences store
 user-specific settings.
 */
@interface ActorService : NSObject

/*! Initialize with database connection. */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) PDSDatabase *database;

/*! Get profile for actor DID. */
- (nullable NSDictionary *)getProfileForActor:(NSString *)actorDID error:(NSError **)error;

/*! Get profiles for multiple actors. */
- (nullable NSArray<NSDictionary *> *)getProfilesForActors:(NSArray<NSString *> *)actorDIDs error:(NSError **)error;

/*! Get preferences for actor. */
- (nullable NSDictionary *)getPreferencesForActor:(NSString *)actorDID error:(NSError **)error;

/*! Update preferences for actor. */
- (BOOL)putPreferencesForActor:(NSString *)actorDID preferences:(NSDictionary *)preferences error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface ActorService : NSObject

- (instancetype)initWithDatabase:(PDSDatabase *)database;

- (nullable NSDictionary *)getProfileForActor:(NSString *)actorDID error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getProfilesForActors:(NSArray<NSString *> *)actorDIDs error:(NSError **)error;

- (nullable NSDictionary *)getPreferencesForActor:(NSString *)actorDID error:(NSError **)error;

- (BOOL)putPreferencesForActor:(NSString *)actorDID preferences:(NSDictionary *)preferences error:(NSError **)error;

/*!
 @method searchActorsTypeahead:limit:error:
 @abstract Searches for actors by handle or display name prefix.
 @param query The search query (handle or name prefix).
 @param limit Maximum number of results (default 10, max 25).
 @param error Error output.
 @return Array of actor dictionaries with did, handle, displayName, avatar.
 */
- (nullable NSArray<NSDictionary *> *)searchActorsTypeahead:(NSString *)query
                                                      limit:(NSInteger)limit
                                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface ActorService : NSObject

- (instancetype)initWithDatabase:(PDSDatabase *)database;

- (nullable NSDictionary *)getProfileForActor:(NSString *)actorDID error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getProfilesForActors:(NSArray<NSString *> *)actorDIDs error:(NSError **)error;

- (nullable NSDictionary *)getPreferencesForActor:(NSString *)actorDID error:(NSError **)error;

- (BOOL)putPreferencesForActor:(NSString *)actorDID preferences:(NSDictionary *)preferences error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

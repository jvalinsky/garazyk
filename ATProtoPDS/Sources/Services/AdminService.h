#import <Foundation/Foundation.h>
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"

NS_ASSUME_NONNULL_BEGIN

@interface AdminService : NSObject

@property (nonatomic, strong, readonly, nullable) PDSDatabasePool *databasePool;
@property (nonatomic, strong, readonly) PDSDatabase *database;

- (instancetype)initWithDatabase:(PDSDatabase *)database databasePool:(nullable PDSDatabasePool *)databasePool;

- (BOOL)disableAccountInvitesForDid:(NSString *)did error:(NSError **)error;
- (BOOL)enableAccountInvitesForDid:(NSString *)did error:(NSError **)error;
- (BOOL)updateEmail:(NSString *)email forAccount:(NSString *)did error:(NSError **)error;
- (BOOL)disableInviteCodes:(BOOL)disabled error:(NSError **)error;

// Invite Code Management
- (nullable NSDictionary *)createInviteCode:(NSDictionary *)params error:(NSError **)error;
- (BOOL)disableInviteCode:(NSString *)code error:(NSError **)error;
- (BOOL)updateAccountPassword:(NSString *)did newPassword:(NSString *)password error:(NSError **)error;
- (BOOL)updateHandle:(NSString *)handle forAccount:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

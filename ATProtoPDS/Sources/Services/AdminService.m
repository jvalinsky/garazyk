#import "AdminService.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

@implementation AdminService

- (instancetype)initWithDatabase:(PDSDatabase *)database databasePool:(nullable PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _database = database;
        _databasePool = databasePool;
    }
    return self;
}

- (BOOL)disableAccountInvitesForDid:(NSString *)did error:(NSError **)error {
    // TODO: Implement actual logic in PDSDatabase/ActorStore
    PDS_LOG_INFO(@"Disabling invites for account: %@", did);
    return YES;
}

- (BOOL)enableAccountInvitesForDid:(NSString *)did error:(NSError **)error {
    // TODO: Implement actual logic in PDSDatabase/ActorStore
    PDS_LOG_INFO(@"Enabling invites for account: %@", did);
    return YES;
}

- (BOOL)updateEmail:(NSString *)email forAccount:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    if (!account) return NO;

    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];

    BOOL success = [self.database updateAccount:account error:error];

    if (success) {
        PDS_LOG_INFO(@"Updated email to %@ for account: %@", email, did);
    }
    return success;
}

- (BOOL)disableInviteCodes:(BOOL)disabled error:(NSError **)error {
    // This might be a global config setting or stored in a settings table
    PDS_LOG_INFO(@"Setting global invite codes disabled: %d", disabled);
    return YES;
}

- (nullable NSDictionary *)createInviteCode:(NSDictionary *)params error:(NSError **)error {
    // TODO: Insert into invite_codes table
    return @{
        @"code": [NSUUID UUID].UUIDString,
        @"available": @1,
        @"disabled": @NO,
        @"forAccount": params[@"forAccount"] ?: @"admin"
    };
}

- (BOOL)disableInviteCode:(NSString *)code error:(NSError **)error {
    // TODO: Update invite_codes table
    PDS_LOG_INFO(@"Disabling invite code: %@", code);
    return YES;
}

- (BOOL)updateAccountPassword:(NSString *)did newPassword:(NSString *)password error:(NSError **)error {
    // TODO: Update password
    PDS_LOG_INFO(@"Updating password for account: %@", did);
    return YES;
}

- (BOOL)updateHandle:(NSString *)handle forAccount:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    if (!account) return NO;

    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];

    BOOL success = [self.database updateAccount:account error:error];

    if (success) {
        PDS_LOG_INFO(@"Updated handle to %@ for account: %@", handle, did);
    }
    return success;
}

@end

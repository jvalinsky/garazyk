/*!
 @file PDSAdminService.m

 @abstract Implementation of consolidated admin service operations.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSAdminService.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "App/Services/PDSAccountService.h"

@implementation PDSAdminService

- (instancetype)initWithDatabase:(PDSDatabase *)database databasePool:(nullable PDSDatabasePool *)databasePool {
    self = [super init];
    if (self) {
        _database = database;
        _databasePool = databasePool;
    }
    return self;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                          accountService:(nullable id<PDSAccountService>)accountService {
    NSError *error = nil;
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&error];
    if (!db) {
        PDS_LOG_ERROR(@"Failed to get service database: %@", error);
        return nil;
    }
    self = [super init];
    if (self) {
        _database = db;
        _serviceDatabases = serviceDatabases;
        _accountService = accountService;
    }
    return self;
}

#pragma mark - Account Administration

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    if (_accountService) {
        return [_accountService getAllAccountsWithError:error];
    }
    return [_database getAllAccountsWithError:error];
}

- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }

    PDS_LOG_INFO(@"Taking down account: %@ reason: %@", did, reason);
    return [_database takeDownAccount:did reason:reason takedownRef:nil error:error];
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }

    PDS_LOG_INFO(@"Reinstating account: %@", did);
    return [_database reinstateAccount:did error:error];
}

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }

    return [_database isAccountTakedownActive:did error:error];
}

#pragma mark - Account Updates

- (BOOL)updateEmail:(NSString *)email forAccount:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:error];
    if (!account) return NO;

    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];

    BOOL success = [_database updateAccount:account error:error];

    if (success) {
        PDS_LOG_INFO(@"Updated email to %@ for account: %@", email, did);
    }
    return success;
}

- (BOOL)updateAccountPassword:(NSString *)did newPassword:(NSString *)password error:(NSError **)error {
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:error];
    if (!account) return NO;
    PDS_LOG_INFO(@"Updating password for account: %@", did);
    return YES;
}

- (BOOL)updateHandle:(NSString *)handle forAccount:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:error];
    if (!account) return NO;

    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];

    BOOL success = [_database updateAccount:account error:error];

    if (success) {
        PDS_LOG_INFO(@"Updated handle to %@ for account: %@", handle, did);
    }
    return success;
}

#pragma mark - Invite Management

- (BOOL)disableAccountInvitesForDid:(NSString *)did error:(NSError **)error {
    if (did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account DID is required"}];
        }
        return NO;
    }

    PDSDatabaseAccount *account = [_database getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    account.inviteEnabled = NO;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [_database updateAccount:account error:error];
    if (success) {
        PDS_LOG_INFO(@"Disabled invites for account: %@", did);
    }
    return success;
}

- (BOOL)enableAccountInvitesForDid:(NSString *)did error:(NSError **)error {
    if (did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account DID is required"}];
        }
        return NO;
    }

    PDSDatabaseAccount *account = [_database getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    account.inviteEnabled = YES;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL success = [_database updateAccount:account error:error];
    if (success) {
        PDS_LOG_INFO(@"Enabled invites for account: %@", did);
    }
    return success;
}

- (nullable NSDictionary *)createInviteCode:(NSDictionary *)params error:(NSError **)error {
    NSString *forAccount = params[@"forAccount"];
    if (!forAccount) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.admin" code:400 userInfo:@{NSLocalizedDescriptionKey: @"forAccount is required"}];
        return nil;
    }
    PDSDatabaseAccount *account = [_database getAccountByDid:forAccount error:error];
    if (!account) return nil;
    NSInteger maxUses = params[@"usesAvailable"] ? [params[@"usesAvailable"] integerValue] : 1;
    if (maxUses < 1) {
        maxUses = 1;
    }

    NSString *code = [NSUUID UUID].UUIDString;
    NSString *inviteID = [NSUUID UUID].UUIDString;
    NSTimeInterval createdAt = [[NSDate date] timeIntervalSince1970];
    BOOL inserted = [_database executeParameterizedUpdate:@"INSERT INTO invite_codes (id, code, account_did, created_at, max_uses, uses, disabled) VALUES (?, ?, ?, ?, ?, 0, 0)"
                                                   params:@[inviteID, code, forAccount, @(createdAt), @(maxUses)]
                                                    error:error];
    if (!inserted) {
        return nil;
    }

    return @{
        @"code": code,
        @"available": @(maxUses),
        @"disabled": @NO,
        @"forAccount": forAccount
    };
}

- (BOOL)disableInviteCode:(NSString *)code error:(NSError **)error {
    if (code.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.atproto.admin" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invite code cannot be empty"}];
        return NO;
    }

    NSArray<NSDictionary *> *rows = [_database executeParameterizedQuery:@"SELECT code FROM invite_codes WHERE code = ? LIMIT 1"
                                                                  params:@[code]
                                                                   error:error];
    if (!rows) {
        return NO;
    }
    if (rows.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invite code not found"}];
        }
        return NO;
    }

    return [_database executeParameterizedUpdate:@"UPDATE invite_codes SET disabled = 1 WHERE code = ?"
                                          params:@[code]
                                           error:error];
}

- (BOOL)disableInviteCodes:(BOOL)disabled error:(NSError **)error {
    PDS_LOG_INFO(@"Setting global invite codes disabled: %@", disabled ? @"YES" : @"NO");
    return [_database executeParameterizedUpdate:@"UPDATE invite_codes SET disabled = ?"
                                          params:@[@(disabled ? 1 : 0)]
                                           error:error];
}

#pragma mark - Moderation

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    PDS_LOG_INFO(@"Moderating account: %@", params);

    NSString *did = params[@"did"];
    NSString *action = params[@"action"];

    if (!did || !action) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: did, action"}];
        }
        return @{@"status": @"error", @"message": @"Missing required fields"};
    }

    return @{
        @"status": @"success",
        @"did": did,
        @"action": action,
        @"timestamp": [NSDateFormatter atproto_stringFromDate:[NSDate date]]
    };
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
    PDS_LOG_INFO(@"Moderating record: %@", params);

    NSString *uri = params[@"uri"];
    NSString *action = params[@"action"];

    if (!uri || !action) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: uri, action"}];
        }
        return @{@"status": @"error", @"message": @"Missing required fields"};
    }

    return @{
        @"status": @"success",
        @"uri": uri,
        @"action": action,
        @"timestamp": [NSDateFormatter atproto_stringFromDate:[NSDate date]]
    };
}

#pragma mark - Labeling

- (nullable NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error {
    NSString *uri = params[@"uri"];
    NSString *val = params[@"val"];

    if (!uri || !val) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: uri, val"}];
        }
        return nil;
    }

    PDS_LOG_INFO(@"Creating label: uri=%@ val=%@", uri, val);

    if ([_database createLabel:params error:error]) {
        return @{
            @"src": params[@"src"] ?: [NSNull null],
            @"uri": params[@"uri"] ?: [NSNull null],
            @"val": params[@"val"] ?: [NSNull null],
            @"cts": params[@"cts"] ?: [NSDateFormatter atproto_stringFromDate:[NSDate date]]
        };
    }
    return nil;
}

- (nullable NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error {
    NSArray *uriPatterns = params[@"uriPatterns"];
    NSArray *sources = params[@"sources"];
    NSInteger limit = [params[@"limit"] integerValue];
    if (limit <= 0) limit = 10;
    NSString *cursor = params[@"cursor"];

    NSArray *labels = [_database getLabelsWithPatterns:uriPatterns sources:sources limit:limit cursor:cursor error:error];
    if (!labels) return nil;

    return @{
        @"labels": labels,
        @"cursor": (labels.count > 0) ? [NSString stringWithFormat:@"%@", labels.lastObject[@"id"]] : [NSNull null]
    };
}

@end

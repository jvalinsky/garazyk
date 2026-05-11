// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "Core/ATProtoValidator.h"
#import "Services/PDS/PDSAccountService.h"

static NSArray<NSString *> *deduplicatedNonEmptyStringArray(id value) {
    if (!value || value == [NSNull null]) {
        return @[];
    }
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id candidate in (NSArray *)value) {
        if (![candidate isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *trimmed = [(NSString *)candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [seen containsObject:trimmed]) {
            continue;
        }
        [seen addObject:trimmed];
        [result addObject:trimmed];
    }
    return result;
}

static NSString *sqlPlaceholders(NSUInteger count) {
    NSMutableArray<NSString *> *placeholders = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger idx = 0; idx < count; idx += 1) {
        [placeholders addObject:@"?"];
    }
    return [placeholders componentsJoinedByString:@", "];
}

static NSString *nullableTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

static NSNumber *moderationAppliedOverrideForAction(NSString *normalizedAction) {
    static NSSet<NSString *> *applyActions = nil;
    static NSSet<NSString *> *clearActions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        applyActions = [NSSet setWithArray:@[
            @"takedown",
            @"suspend",
            @"deactivate",
            @"disable",
            @"remove",
            @"delete",
            @"hide",
            @"block",
            @"ban"
        ]];
        clearActions = [NSSet setWithArray:@[
            @"untakedown",
            @"reinstate",
            @"unsuspend",
            @"reactivate",
            @"enable",
            @"restore",
            @"unhide",
            @"unblock",
            @"unban",
            @"clear"
        ]];
    });

    if ([applyActions containsObject:normalizedAction]) {
        return @1;
    }
    if ([clearActions containsObject:normalizedAction]) {
        return @0;
    }
    return nil;
}

@interface PDSAdminService ()
- (nullable NSString *)resolveAccountIdentifierToDid:(NSString *)accountIdentifier error:(NSError **)error;
- (BOOL)persistModerationActionForSubjectType:(NSString *)subjectType
                                     subjectId:(NSString *)subjectId
                                        action:(NSString *)action
                                        reason:(nullable NSString *)reason
                                          note:(nullable NSString *)note
                                    timestamp:(NSString *)timestamp
                                         error:(NSError **)error;
@end

@implementation PDSAdminService

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

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

- (BOOL)deactivateAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error {
    if (!did || did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is required"}];
        }
        return NO;
    }

    PDS_LOG_INFO(@"Deactivating account: %@ reason: %@", did, reason);
    return [_database deactivateAccount:did error:error];
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

// Direct DB update only — does NOT update PLC directory or emit firehose identity events.
// For full protocol-compliant updates, use com.atproto.identity.updateHandle XRPC endpoint.
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

- (BOOL)disableInviteCodesWithCodes:(nullable NSArray<NSString *> *)codes
                           accounts:(nullable NSArray<NSString *> *)accounts
                              error:(NSError **)error {
    NSArray<NSString *> *validatedCodes = deduplicatedNonEmptyStringArray(codes);
    NSArray<NSString *> *accountIdentifiers = deduplicatedNonEmptyStringArray(accounts);
    if (validatedCodes.count == 0 && accountIdentifiers.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"At least one of codes or accounts must be provided"}];
        }
        return NO;
    }

    NSMutableArray<NSString *> *resolvedDids = [NSMutableArray array];
    NSMutableSet<NSString *> *seenDids = [NSMutableSet set];
    for (NSString *identifier in accountIdentifiers) {
        NSError *resolveError = nil;
        NSString *did = [self resolveAccountIdentifierToDid:identifier error:&resolveError];
        if (!did) {
            if (error) {
                *error = resolveError;
            }
            return NO;
        }
        if (![seenDids containsObject:did]) {
            [seenDids addObject:did];
            [resolvedDids addObject:did];
        }
    }

    if (validatedCodes.count > 0) {
        NSString *codeSQL = [NSString stringWithFormat:@"UPDATE invite_codes SET disabled = 1 WHERE code IN (%@)",
                                                        sqlPlaceholders(validatedCodes.count)];
        if (![_database executeParameterizedUpdate:codeSQL params:validatedCodes error:error]) {
            return NO;
        }
    }

    if (resolvedDids.count > 0) {
        NSString *accountSQL = [NSString stringWithFormat:@"UPDATE invite_codes SET disabled = 1 WHERE account_did IN (%@)",
                                                           sqlPlaceholders(resolvedDids.count)];
        if (![_database executeParameterizedUpdate:accountSQL params:resolvedDids error:error]) {
            return NO;
        }
    }

    return YES;
}

#pragma mark - Moderation

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    PDS_LOG_INFO(@"Moderating account: %@", params);

    NSString *did = nullableTrimmedString(params[@"did"]);
    NSString *action = nullableTrimmedString(params[@"action"]);

    if (did.length == 0 || action.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: did, action"}];
        }
        return @{@"status": @"error", @"message": @"Missing required fields"};
    }

    NSError *didValidationError = nil;
    if (![ATProtoValidator validateDID:did error:&didValidationError]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    didValidationError.localizedDescription ?: @"Invalid DID"}];
        }
        return @{@"status": @"error", @"message": @"Invalid DID"};
    }

    NSError *lookupError = nil;
    PDSDatabaseAccount *account = [_database getAccountByDid:did error:&lookupError];
    if (!account) {
        if (error) {
            *error = lookupError ?: [NSError errorWithDomain:@"com.atproto.admin"
                                                         code:404
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return @{@"status": @"error", @"message": @"Account not found"};
    }

    NSString *timestamp = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    if (![self persistModerationActionForSubjectType:@"account"
                                           subjectId:did
                                              action:action
                                              reason:nullableTrimmedString(params[@"reason"])
                                                note:nullableTrimmedString(params[@"note"])
                                          timestamp:timestamp
                                               error:error]) {
        return @{@"status": @"error", @"message": (error && *error) ? (*error).localizedDescription : @"Moderation persistence failed"};
    }

    return @{
        @"status": @"success",
        @"did": account.did ?: did,
        @"action": action,
        @"timestamp": timestamp
    };
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
    PDS_LOG_INFO(@"Moderating record: %@", params);

    NSString *uri = nullableTrimmedString(params[@"uri"]);
    NSString *action = nullableTrimmedString(params[@"action"]);

    if (uri.length == 0 || action.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSAdminServiceErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing required fields: uri, action"}];
        }
        return @{@"status": @"error", @"message": @"Missing required fields"};
    }

    if (![uri hasPrefix:@"at://"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT-URI"}];
        }
        return @{@"status": @"error", @"message": @"Invalid AT-URI"};
    }

    NSString *timestamp = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    if (![self persistModerationActionForSubjectType:@"record"
                                           subjectId:uri
                                              action:action
                                              reason:nullableTrimmedString(params[@"reason"])
                                                note:nullableTrimmedString(params[@"note"])
                                          timestamp:timestamp
                                               error:error]) {
        return @{@"status": @"error", @"message": (error && *error) ? (*error).localizedDescription : @"Moderation persistence failed"};
    }

    return @{
        @"status": @"success",
        @"uri": uri,
        @"action": action,
        @"timestamp": timestamp
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

- (nullable NSString *)resolveAccountIdentifierToDid:(NSString *)accountIdentifier error:(NSError **)error {
    NSString *identifier = nullableTrimmedString(accountIdentifier);
    if (identifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid account identifier"}];
        }
        return nil;
    }

    if ([ATProtoValidator validateDID:identifier error:nil]) {
        PDSDatabaseAccount *account = [_database getAccountByDid:identifier error:error];
        if (!account) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
            }
            return nil;
        }
        return account.did;
    }

    PDSDatabaseAccount *account = [_database getAccountByHandle:identifier error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return nil;
    }
    return account.did;
}

- (BOOL)persistModerationActionForSubjectType:(NSString *)subjectType
                                     subjectId:(NSString *)subjectId
                                        action:(NSString *)action
                                        reason:(nullable NSString *)reason
                                          note:(nullable NSString *)note
                                    timestamp:(NSString *)timestamp
                                         error:(NSError **)error {
    NSString *normalizedAction = [action lowercaseString];
    NSNumber *appliedOverride = moderationAppliedOverrideForAction(normalizedAction);

    NSInteger appliedValue = 0;
    if (appliedOverride) {
        appliedValue = appliedOverride.integerValue;
    } else {
        NSArray<NSDictionary *> *rows = [_database executeParameterizedQuery:
                                         @"SELECT applied FROM admin_takedowns WHERE subjectType = ? AND subjectId = ? ORDER BY createdAt DESC LIMIT 1"
                                                                  params:@[subjectType, subjectId]
                                                                   error:error];
        if (!rows) {
            return NO;
        }

        if (rows.count > 0) {
            id existingApplied = rows.firstObject[@"applied"];
            appliedValue = [existingApplied respondsToSelector:@selector(integerValue)] ? [existingApplied integerValue] : 0;
        }
    }

    NSString *storedReason = nil;
    if (reason.length > 0 && note.length > 0) {
        storedReason = [NSString stringWithFormat:@"%@ | note: %@", reason, note];
    } else if (reason.length > 0) {
        storedReason = reason;
    } else if (note.length > 0) {
        storedReason = [NSString stringWithFormat:@"note: %@", note];
    }

    NSString *eventID = [[NSUUID UUID] UUIDString];
    NSString *sql = @"INSERT OR REPLACE INTO admin_takedowns (id, subjectType, subjectId, reason, takedownRef, applied, createdBy, createdAt) VALUES (?, ?, ?, ?, ?, ?, 'admin', ?)";
    NSArray *params = @[
        eventID,
        subjectType,
        subjectId,
        storedReason ?: [NSNull null],
        action,
        @(appliedValue),
        timestamp
    ];
    return [_database executeParameterizedUpdate:sql params:params error:error];
}

#pragma mark - Server Statistics

- (nullable NSDictionary *)getServerStatsWithError:(NSError **)error {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    
    // Account counts
    NSArray *accounts = [_database executeQuery:@"SELECT COUNT(*) as count FROM accounts" error:error];
    if (accounts.count > 0) {
        stats[@"accounts_total"] = accounts.firstObject[@"count"] ?: @0;
    }
    
    // Active accounts (with repos)
    NSArray *repos = [_database executeQuery:@"SELECT COUNT(*) as count FROM repos" error:error];
    if (repos.count > 0) {
        stats[@"repos_total"] = repos.firstObject[@"count"] ?: @0;
    }
    
    // Record count
    NSArray *records = [_database executeQuery:@"SELECT COUNT(*) as count FROM records" error:error];
    if (records.count > 0) {
        stats[@"records_total"] = records.firstObject[@"count"] ?: @0;
    }
    
    // Blob count and size
    NSArray *blobs = [_database executeQuery:@"SELECT COUNT(*) as count, COALESCE(SUM(size), 0) as total_size FROM blobs" error:error];
    if (blobs.count > 0) {
        stats[@"blobs_total"] = blobs.firstObject[@"count"] ?: @0;
        stats[@"blobs_size_bytes"] = blobs.firstObject[@"total_size"] ?: @0;
    }
    
    // Block count
    NSArray *blocks = [_database executeQuery:@"SELECT COUNT(*) as count FROM blocks" error:error];
    if (blocks.count > 0) {
        stats[@"blocks_total"] = blocks.firstObject[@"count"] ?: @0;
    }
    
    // Invite code stats
    NSArray *invites = [_database executeQuery:@"SELECT COUNT(*) as total, SUM(CASE WHEN disabled = 0 THEN 1 ELSE 0 END) as active FROM invite_codes" error:error];
    if (invites.count > 0) {
        stats[@"invite_codes_total"] = invites.firstObject[@"total"] ?: @0;
        stats[@"invite_codes_active"] = invites.firstObject[@"active"] ?: @0;
    }
    
    // Open reports count
    NSArray *reports = [_database executeQuery:@"SELECT COUNT(*) as count FROM reports WHERE status = 'open'" error:error];
    if (reports.count > 0) {
        stats[@"reports_open"] = reports.firstObject[@"count"] ?: @0;
    }
    
    // Recent signups (last 7 days)
    NSString *sevenDaysAgo = [NSDateFormatter atproto_stringFromDate:[[NSDate date] dateByAddingTimeInterval:-7*24*60*60]];
    NSArray *recentSignups = [_database executeParameterizedQuery:@"SELECT COUNT(*) as count FROM accounts WHERE created_at >= ?" params:@[sevenDaysAgo] error:error];
    if (recentSignups.count > 0) {
        stats[@"recent_signups_7d"] = recentSignups.firstObject[@"count"] ?: @0;
    }
    
    return stats;
}

#pragma mark - Audit Logging

- (BOOL)logAdminAction:(NSString *)action
           subjectType:(nullable NSString *)subjectType
             subjectId:(nullable NSString *)subjectId
               details:(nullable NSDictionary *)details
              ipAddress:(nullable NSString *)ipAddress
               adminDid:(NSString *)adminDid
                  error:(NSError **)error {
    NSString *detailsJson = nil;
    if (details) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:details options:0 error:nil];
        if (jsonData) {
            detailsJson = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
    }
    
    NSDictionary *entry = @{
        @"admin_did": adminDid ?: @"unknown",
        @"action": action ?: @"unknown",
        @"subject_type": subjectType ?: [NSNull null],
        @"subject_id": subjectId ?: [NSNull null],
        @"details": detailsJson ?: [NSNull null],
        @"ip_address": ipAddress ?: [NSNull null]
    };
    
    return [_database insertAuditLogEntry:entry error:error];
}

- (nullable NSDictionary *)queryAuditLog:(NSDictionary *)filters
                                   limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                   error:(NSError **)error {
    if (limit <= 0) limit = 50;
    
    NSArray *entries = [_database queryAuditLog:filters limit:limit cursor:cursor error:error];
    if (!entries) return nil;
    
    NSString *nextCursor = nil;
    if (entries.count > 0) {
        nextCursor = [NSString stringWithFormat:@"%@", entries.lastObject[@"id"]];
    }
    
    return @{
        @"entries": entries,
        @"cursor": nextCursor ?: [NSNull null]
    };
}

#pragma mark - Reports

- (nullable NSDictionary *)createReport:(NSDictionary *)params error:(NSError **)error {
    NSString *reportId = [_database createReport:params error:error];
    if (!reportId) return nil;
    
    return @{
        @"id": reportId,
        @"reasonType": params[@"reason_type"] ?: [NSNull null],
        @"reason": params[@"reason"] ?: [NSNull null],
        @"reportedBy": params[@"reported_by_did"] ?: [NSNull null],
        @"subject": @{
            @"$type": params[@"subject_type"] ?: @"unknown",
            @"did": params[@"subject_did"] ?: [NSNull null],
            @"uri": params[@"subject_uri"] ?: [NSNull null]
        },
        @"createdAt": [NSDateFormatter atproto_stringFromDate:[NSDate date]]
    };
}

- (nullable NSDictionary *)queryReports:(NSDictionary *)filters
                                  limit:(NSInteger)limit
                                cursor:(nullable NSString *)cursor
                                  error:(NSError **)error {
    if (limit <= 0) limit = 50;
    
    NSArray *reports = [_database queryReports:filters limit:limit cursor:cursor error:error];
    if (!reports) return nil;
    
    NSString *nextCursor = nil;
    if (reports.count > 0) {
        nextCursor = [NSString stringWithFormat:@"%@", reports.lastObject[@"id"]];
    }
    
    return @{
        @"reports": reports,
        @"cursor": nextCursor ?: [NSNull null]
    };
}

- (BOOL)resolveReport:(NSString *)reportId
               status:(NSString *)status
            resolvedBy:(nullable NSString *)resolvedBy
                notes:(nullable NSString *)notes
                error:(NSError **)error {
    return [_database updateReportStatus:reportId status:status resolvedBy:resolvedBy notes:notes error:error];
}

@end

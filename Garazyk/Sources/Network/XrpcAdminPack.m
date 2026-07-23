// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAdminPack.m
//  ATProtoPDS
//
//  Domain module for com.atproto.admin.* XRPC endpoints.
//

#import "Network/XrpcAdminPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabase+Moderation.h"
#import "Admin/PDSAdminController.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Services/PDS/PDSRecordService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Admin/Diagnostics/BlobAudit/PDSBlobAuditManager.h"
#import "Core/ATProtoValidator.h"
#import "Core/ATURI.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Network/XrpcAdminPack+AccountLookup.h"
#import "Network/XrpcAdminPack+ServerStats.h"
#import "Network/XrpcAdminPack+AccountInfo.h"
#import "Network/XrpcAdminPack+Lifecycle.h"
#import "Network/XrpcAdminPack+Moderation.h"
#import "Network/XrpcServerPack_Internal.h"

// Forward declarations of helper functions — static helpers are local; non-static are shared with categories
NSDictionary *adminAccountViewFromAccount(PDSDatabaseAccount *account);
static NSString *iso8601StringFromUnixTimestamp(NSTimeInterval timestamp);
NSArray<NSString *> *queryArrayValues(HttpRequest *request, NSString *key);
static NSDictionary *adminInviteCodeViewFromRow(NSDictionary *row);
NSArray<NSDictionary *> *loadAdminInviteCodeViews(PDSServiceDatabases *serviceDatabases,
                                                         NSString *sort,
                                                         NSInteger limit,
                                                         NSInteger offset,
                                                         NSError **error);
BOOL setInviteEnabledForAccount(PDSServiceDatabases *serviceDatabases,
                                       NSString *did,
                                       BOOL enabled,
                                       NSError **error);
BOOL deleteAccountAsAdmin(PDSServiceDatabases *serviceDatabases,
                                 NSString *did,
                                 NSError **error);
BOOL updateAccountPassword(PDSServiceDatabases *serviceDatabases,
                                  NSString *did,
                                  NSString *password,
                                  NSError **error);
BOOL updateAccountSigningKey(PDSServiceDatabases *serviceDatabases,
                                    NSString *did,
                                    NSString *signingKey,
                                    NSError **error);
NSDictionary *subjectStatusSubjectFromRequestBody(NSDictionary *body);
BOOL parseStrictIntegerString(NSString *str, NSInteger *outValue);
BOOL resolveAccountIdentifierToDid(PDSServiceDatabases *serviceDatabases,
                                          NSString *identifier,
                                          NSString **outDid,
                                          NSError **error);
static BOOL executeServiceUpdate(PDSDatabase *db,
                                 NSString *sql,
                                 NSArray *params,
                                 BOOL ignoreMissingTable,
                                 NSError **error);
static BOOL isNoSuchTableError(NSError *error);
static NSData *generateAccountPasswordSalt(void);
NSArray<NSString *> *validatedUniqueStringArrayFromJSONValue(id value,
                                                                     NSString *fieldName,
                                                                     NSError **error);

@implementation XrpcAdminPack

+ (NSString *)routePackIdentifier {
  return @"com.atproto.admin";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    // Account Lookup, Search & Email
    [self registerAccountLookupEndpoints:dispatcher services:services];

    // Server Stats, Audit & Repair
    [self registerServerStatsEndpoints:dispatcher services:services];

    // Account Info, Invites & Subject Status
    [self registerAccountInfoEndpoints:dispatcher services:services];

    // Account Lifecycle, Records & Takedown
    [self registerLifecycleEndpoints:dispatcher services:services];

    // Moderation (deprecated)
    [self registerModerationEndpoints:dispatcher services:services];
}

@end


#pragma mark - Helper Functions

NSArray<NSString *> *validatedUniqueStringArrayFromJSONValue(id value,
                                                                     NSString *fieldName,
                                                                     NSError **error) {
    if (!value) {
        return @[];
    }
    if (![value isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"%@ must be an array of strings", fieldName ?: @"field"]}];
        }
        return nil;
    }

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id rawValue in (NSArray *)value) {
        if (![rawValue isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"%@ must contain only strings", fieldName ?: @"field"]}];
            }
            return nil;
        }
        NSString *trimmed = [(NSString *)rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"%@ cannot contain empty strings", fieldName ?: @"field"]}];
            }
            return nil;
        }
        if (![seen containsObject:trimmed]) {
            [seen addObject:trimmed];
            [values addObject:trimmed];
        }
    }

    return values;
}

BOOL updateAccountSigningKey(PDSServiceDatabases *serviceDatabases,
                                    NSString *did,
                                    NSString *signingKey,
                                    NSError **error) {
    if (![signingKey hasPrefix:@"did:key:"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"signingKey must be a did:key identifier"}];
        }
        return NO;
    }

    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    GZ_LOG_WARN(@"updateAccountSigningKey accepted but no DID document persistence is configured for DID %@ (signingKey=%@)", did, signingKey);
    return YES;
}

static NSString *iso8601StringFromUnixTimestamp(NSTimeInterval timestamp) {
    NSDate *date = timestamp > 0 ? [NSDate dateWithTimeIntervalSince1970:timestamp] : [NSDate date];
    return [NSDateFormatter atproto_stringFromDate:date];
}

NSDictionary *adminAccountViewFromAccount(PDSDatabaseAccount *account) {
    NSMutableDictionary *view = [@{
        @"did": account.did ?: @"",
        @"handle": account.handle ?: @"",
        @"indexedAt": iso8601StringFromUnixTimestamp(account.createdAt)
    } mutableCopy];

    if (account.email.length > 0) {
        view[@"email"] = account.email;
    }

    return view;
}

NSArray<NSString *> *queryArrayValues(HttpRequest *request, NSString *key) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSArray<NSString *> *pairs = [request.queryString componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        if (pair.length == 0) {
            continue;
        }
        NSRange eqRange = [pair rangeOfString:@"="];
        NSString *rawKey = eqRange.location == NSNotFound ? pair : [pair substringToIndex:eqRange.location];
        NSString *rawValue = eqRange.location == NSNotFound ? @"" : [pair substringFromIndex:eqRange.location + 1];

        NSString *decodedKey = [[rawKey stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: rawKey;
        if (![decodedKey isEqualToString:key]) {
            continue;
        }

        NSString *decodedValue = [[rawValue stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: rawValue;
        for (NSString *component in [decodedValue componentsSeparatedByString:@","]) {
            NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [values addObject:trimmed];
            }
        }
    }

    if (values.count == 0) {
        NSString *singleValue = [request queryParamForKey:key];
        for (NSString *component in [singleValue componentsSeparatedByString:@","]) {
            NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [values addObject:trimmed];
            }
        }
    }

    return values;
}

static NSDictionary *adminInviteCodeViewFromRow(NSDictionary *row) {
    NSString *code = [row[@"code"] isKindOfClass:[NSString class]] ? row[@"code"] : @"";
    NSString *accountDid = [row[@"account_did"] isKindOfClass:[NSString class]] ? row[@"account_did"] : @"";
    NSInteger uses = [row[@"uses"] respondsToSelector:@selector(integerValue)] ? [row[@"uses"] integerValue] : 0;
    NSInteger maxUses = [row[@"max_uses"] respondsToSelector:@selector(integerValue)] ? [row[@"max_uses"] integerValue] : 1;
    if (maxUses < 0) {
        maxUses = 0;
    }
    NSInteger available = maxUses - uses;
    if (available < 0) {
        available = 0;
    }
    BOOL disabled = [row[@"disabled"] respondsToSelector:@selector(boolValue)] ? [row[@"disabled"] boolValue] : NO;
    NSTimeInterval createdAt = [row[@"created_at"] respondsToSelector:@selector(doubleValue)] ? [row[@"created_at"] doubleValue] : 0;

    return @{
        @"code": code,
        @"available": @(available),
        @"disabled": @(disabled),
        @"forAccount": accountDid,
        @"createdBy": accountDid,
        @"createdAt": iso8601StringFromUnixTimestamp(createdAt),
        @"uses": @[]
    };
}

NSArray<NSDictionary *> *loadAdminInviteCodeViews(PDSServiceDatabases *serviceDatabases,
                                                          NSString *sort,
                                                          NSInteger limit,
                                                          NSInteger offset,
                                                          NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    // Whitelist allowed sort values to prevent SQL injection
    NSString *orderBy = nil;
    if ([sort isEqualToString:@"usage"]) {
        orderBy = @"uses DESC, created_at DESC, code ASC";
    } else if ([sort isEqualToString:@"created_at"] || [sort isEqualToString:@"code"] || [sort isEqualToString:@"uses"]) {
        orderBy = [NSString stringWithFormat:@"%@ DESC", sort];
    } else {
        orderBy = @"created_at DESC, code ASC";
    }
    NSString *sql = [NSString stringWithFormat:
                     @"SELECT code, account_did, created_at, uses, max_uses, disabled "
                     @"FROM invite_codes ORDER BY %@ LIMIT ? OFFSET ?", orderBy];
    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:sql
                                                           params:@[@(limit), @(offset)]
                                                            error:error];
    [db close];
    if (!rows) {
        return nil;
    }

    NSMutableArray<NSDictionary *> *codes = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        [codes addObject:adminInviteCodeViewFromRow(row)];
    }
    return codes;
}

static BOOL isNoSuchTableError(NSError *error) {
    if (!error) {
        return NO;
    }
    NSString *message = [error.localizedDescription lowercaseString];
    return [message containsString:@"no such table"];
}

static BOOL executeServiceUpdate(PDSDatabase *db,
                                 NSString *sql,
                                 NSArray *params,
                                 BOOL ignoreMissingTable,
                                 NSError **error) {
    NSError *updateError = nil;
    BOOL success = [db executeParameterizedUpdate:sql params:params error:&updateError];
    if (success || (ignoreMissingTable && isNoSuchTableError(updateError))) {
        return YES;
    }
    if (error) {
        *error = updateError ?: [NSError errorWithDomain:@"com.atproto.admin"
                                                    code:500
                                                userInfo:@{NSLocalizedDescriptionKey: @"Database update failed"}];
    }
    return NO;
}

BOOL setInviteEnabledForAccount(PDSServiceDatabases *serviceDatabases,
                                       NSString *did,
                                       BOOL enabled,
                                       NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    account.inviteEnabled = enabled;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    BOOL updated = [db updateAccount:account error:error];
    return updated;
}

BOOL deleteAccountAsAdmin(PDSServiceDatabases *serviceDatabases,
                                 NSString *did,
                                 NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return NO;
    }

    PDSDatabaseAccount *account = [db getAccountByDid:did error:error];
    if (!account) {
        [db close];
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    NSArray<NSString *> *cleanupSQL = @[
        @"DELETE FROM refresh_tokens WHERE account_did = ?",
        @"DELETE FROM app_passwords WHERE account_did = ?",
        @"DELETE FROM invite_codes WHERE account_did = ?",
        @"DELETE FROM passkeys WHERE account_did = ?"
    ];
    for (NSString *sql in cleanupSQL) {
        if (!executeServiceUpdate(db, sql, @[did], YES, error)) {
            [db close];
            return NO;
        }
    }

    BOOL deleted = [db deleteAccount:did error:error];
    [db close];
    return deleted;
}

NSDictionary *subjectStatusSubjectFromRequestBody(NSDictionary *body) {
    id subjectValue = body[@"subject"];
    if (![subjectValue isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSDictionary *subject = (NSDictionary *)subjectValue;
    NSString *did = [subject[@"did"] isKindOfClass:[NSString class]] ? subject[@"did"] : nil;
    NSString *uri = [subject[@"uri"] isKindOfClass:[NSString class]] ? subject[@"uri"] : nil;
    if (uri.length == 0 && [subject[@"$type"] isEqualToString:@"com.atproto.repo.strongRef"]) {
        uri = [subject[@"uri"] isKindOfClass:[NSString class]] ? subject[@"uri"] : nil;
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (did.length > 0) result[@"did"] = did;
    if (uri.length > 0) result[@"uri"] = uri;
    return result;
}

static NSData *generateAccountPasswordSalt(void) {
    NSMutableData *salt = [NSMutableData dataWithLength:32];
    uuid_t firstUUID;
    uuid_t secondUUID;
    [[NSUUID UUID] getUUIDBytes:firstUUID];
    [[NSUUID UUID] getUUIDBytes:secondUUID];
    [salt replaceBytesInRange:NSMakeRange(0, 16) withBytes:firstUUID];
    [salt replaceBytesInRange:NSMakeRange(16, 16) withBytes:secondUUID];
    return salt;
}

BOOL updateAccountPassword(PDSServiceDatabases *serviceDatabases,
                                  NSString *did,
                                  NSString *password,
                                  NSError **error) {
    PDSDatabaseAccount *account = [serviceDatabases getAccountByDid:did error:error];
    if (!account) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    if (password.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing password"}];
        }
        return NO;
    }

    NSData *salt = account.passwordSalt;
    if (salt.length == 0) {
        salt = generateAccountPasswordSalt();
    }

    NSError *hashError = nil;
    NSData *hash = pbkdf2HashPassword(password, salt, &hashError);
    if (!hash) {
        if (error) {
            *error = hashError ?: [NSError errorWithDomain:@"com.atproto.admin"
                                                      code:500
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to hash password"}];
        }
        return NO;
    }

    account.passwordSalt = salt;
    account.passwordHash = hash;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    if (![serviceDatabases updateAccount:account error:error]) {
        return NO;
    }

    [serviceDatabases deleteRefreshTokensForAccount:did error:nil];
    return YES;
}

BOOL parseStrictIntegerString(NSString *value, NSInteger *outValue) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    NSInteger parsed = 0;
    if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
        return NO;
    }
    if (outValue) {
        *outValue = parsed;
    }
    return YES;
}

BOOL resolveAccountIdentifierToDid(PDSServiceDatabases *serviceDatabases,
                                          NSString *accountIdentifier,
                                          NSString **outDid,
                                          NSError **error) {
    return [XrpcIdentityHelper resolveAccountIdentifierToDid:accountIdentifier
                                            serviceDatabases:serviceDatabases
                                                      outDid:outDid
                                                       error:error];
}

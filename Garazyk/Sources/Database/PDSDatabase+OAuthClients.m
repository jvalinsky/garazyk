// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+OAuthClients.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (OAuthClients)

- (nullable NSDictionary *)getOAuthClientWithID:(NSString *)clientID error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT client_id, client_secret, redirect_uris, grant_types, scope FROM oauth_clients WHERE client_id = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    ATProtoDBBindValue(stmt, 1, clientID);

    NSDictionary *client = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"client_id"] = [self valueFromStatement:stmt columnIndex:0];

        id secret = [self valueFromStatement:stmt columnIndex:1];
        if (secret) dict[@"client_secret"] = secret;

        id redirectUrisStr = [self valueFromStatement:stmt columnIndex:2];
        if (redirectUrisStr) {
            NSArray *uris = [redirectUrisStr componentsSeparatedByString:@" "];
            dict[@"redirect_uris"] = uris;
        } else {
            dict[@"redirect_uris"] = @[];
        }

        id grants = [self valueFromStatement:stmt columnIndex:3];
        if (grants) dict[@"grant_types"] = grants;

        id scope = [self valueFromStatement:stmt columnIndex:4];
        if (scope) dict[@"scope"] = scope;

        client = dict;
    }

    result = client;

    return;
    }];
    return result;
}

- (BOOL)createOAuthClient:(NSDictionary *)client error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO oauth_clients (client_id, client_secret, redirect_uris, grant_types, scope, created_at) VALUES (?, ?, ?, ?, ?, ?)";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    NSString *clientID = client[@"client_id"];
    ATProtoDBBindValue(stmt, 1, clientID);

    NSString *secret = client[@"client_secret"];
    ATProtoDBBindValue(stmt, 2, secret);

    NSArray *redirectURIs = client[@"redirect_uris"];
    NSString *redirectURIsString = @"";
    if ([redirectURIs isKindOfClass:[NSArray class]] && redirectURIs.count > 0) {
        redirectURIsString = [redirectURIs componentsJoinedByString:@" "];
    }
    ATProtoDBBindValue(stmt, 3, redirectURIsString);

    NSString *grants = client[@"grant_types"];
    ATProtoDBBindValue(stmt, 4, grants);

    NSString *scope = client[@"scope"];
    ATProtoDBBindValue(stmt, 5, scope);

    ATProtoDBBindValue(stmt, 6, [NSDateFormatter atproto_stringFromDate:[NSDate date]]);

    rc = sqlite3_step(stmt);

    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = YES;

    return;
    }];
    return result;
}

- (nullable NSArray<NSDictionary *> *)getAllOAuthClientsWithError:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT client_id, client_secret, redirect_uris, grant_types, scope FROM oauth_clients";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    NSMutableArray *clients = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"client_id"] = [self valueFromStatement:stmt columnIndex:0];

        id secret = [self valueFromStatement:stmt columnIndex:1];
        if (secret) dict[@"client_secret"] = secret;

        id redirectUrisStr = [self valueFromStatement:stmt columnIndex:2];
        if (redirectUrisStr) {
            NSArray *uris = [redirectUrisStr componentsSeparatedByString:@" "];
            dict[@"redirect_uris"] = uris;
        } else {
            dict[@"redirect_uris"] = @[];
        }

        id grants = [self valueFromStatement:stmt columnIndex:3];
        if (grants) dict[@"grant_types"] = grants;

        id scope = [self valueFromStatement:stmt columnIndex:4];
        if (scope) dict[@"scope"] = scope;

        [clients addObject:dict];
    }

    result = clients;

    return;
    }];
    return result;
}

- (BOOL)deleteOAuthClientWithID:(NSString *)clientID error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"DELETE FROM oauth_clients WHERE client_id = ?";

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    ATProtoDBBindValue(stmt, 1, clientID);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    result = sqlite3_changes(self.db) > 0;

    return;
    }];
    return result;
}

@end

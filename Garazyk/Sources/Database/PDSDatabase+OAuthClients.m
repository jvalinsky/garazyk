// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+OAuthClients.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (OAuthClients)

- (NSDictionary *)getClientWithID:(NSString *)clientID error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM oauth_clients WHERE client_id = ?";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = nil;
        return;
    }

    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

    NSDictionary *client = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"client_id"] = @((const char *)sqlite3_column_text(stmt, 0));

        const char *secret = (const char *)sqlite3_column_text(stmt, 1);
        if (secret) dict[@"client_secret"] = @(secret);

        const char *redirectUrisStr = (const char *)sqlite3_column_text(stmt, 2);
        if (redirectUrisStr) {
            NSString *urisString = @(redirectUrisStr);
            NSArray *uris = [urisString componentsSeparatedByString:@" "];
            dict[@"redirect_uris"] = uris;
        } else {
            dict[@"redirect_uris"] = @[];
        }

        const char *grants = (const char *)sqlite3_column_text(stmt, 3);
        if (grants) dict[@"grant_types"] = @(grants);

        const char *scope = (const char *)sqlite3_column_text(stmt, 4);
        if (scope) dict[@"scope"] = @(scope);

        client = dict;
    }

    result = client;

    return;
    }];
    return result;
}

- (BOOL)createClient:(NSDictionary *)client error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT OR REPLACE INTO oauth_clients (client_id, client_secret, redirect_uris, grant_types, scope, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    NSString *clientID = client[@"client_id"];
    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

    NSString *secret = client[@"client_secret"];
    if (secret) sqlite3_bind_text(stmt, 2, secret.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 2);

    NSArray *redirectURIs = client[@"redirect_uris"];
    NSString *redirectURIsString = @"";
    if ([redirectURIs isKindOfClass:[NSArray class]] && redirectURIs.count > 0) {
        redirectURIsString = [redirectURIs componentsJoinedByString:@" "];
    }
    sqlite3_bind_text(stmt, 3, redirectURIsString.UTF8String, -1, SQLITE_STATIC);

    NSString *grants = client[@"grant_types"];
    if (grants) sqlite3_bind_text(stmt, 4, grants.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 4);

    NSString *scope = client[@"scope"];
    if (scope) sqlite3_bind_text(stmt, 5, scope.UTF8String, -1, SQLITE_STATIC);
    else sqlite3_bind_null(stmt, 5);

    sqlite3_bind_text(stmt, 6, [self iso8601StringFromDate:[NSDate date]].UTF8String, -1, SQLITE_STATIC);

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

- (BOOL)seedTestClient:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    #ifndef DEBUG
    if (error) {
        *error = [NSError errorWithDomain:@"PDSDatabase"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Test client seeding disabled in release builds"}];
    }
    result = NO;
    return;
    #else
    NSDictionary *testClient = @{
        @"client_id": @"test-client",
        @"redirect_uris": @[@"http://localhost:3000/callback", @"http://localhost:8080/callback", @"https://localhost:2583/oauth-demo/callback", @"http://localhost:2583/oauth-demo/callback", @"https://127.0.0.1:2583/oauth-demo/callback", @"http://127.0.0.1:2583/oauth-demo/callback", @"http://localhost:2583/?oauth_callback=1", @"http://127.0.0.1:2583/?oauth_callback=1", @"http://localhost:8080/?oauth_callback=1", @"http://127.0.0.1:8080/?oauth_callback=1"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    [self createClient:testClient error:error];

    NSDictionary *confidentialClient = @{
        @"client_id": @"test-client-confidential",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://localhost:3000/callback"],
        @"grant_types": @"authorization_code,refresh_token",
        @"scope": @"atproto"
    };
    result = [self createClient:confidentialClient error:error];
    return;
    #endif
    }];
    return result;
}

- (NSArray<NSDictionary *> *)getAllOAuthClientsWithError:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM oauth_clients ORDER BY created_at DESC";
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
        dict[@"client_id"] = @((const char *)sqlite3_column_text(stmt, 0));

        const char *secret = (const char *)sqlite3_column_text(stmt, 1);
        if (secret) dict[@"client_secret"] = @(secret);

        const char *redirectUrisStr = (const char *)sqlite3_column_text(stmt, 2);
        if (redirectUrisStr) {
            NSString *urisString = @(redirectUrisStr);
            NSArray *uris = [urisString componentsSeparatedByString:@" "];
            dict[@"redirect_uris"] = uris;
        } else {
            dict[@"redirect_uris"] = @[];
        }

        const char *grants = (const char *)sqlite3_column_text(stmt, 3);
        if (grants) dict[@"grant_types"] = @(grants);

        const char *scope = (const char *)sqlite3_column_text(stmt, 4);
        if (scope) dict[@"scope"] = @(scope);

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

    sqlite3_bind_text(stmt, 1, clientID.UTF8String, -1, SQLITE_STATIC);

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

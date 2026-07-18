// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+OAuthClients.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

static NSSet<NSString *> *PDSOAuthClientColumns(sqlite3 *db) {
    NSMutableSet<NSString *> *columns = [NSMutableSet set];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "PRAGMA table_info(oauth_clients)", -1, &stmt, NULL) != SQLITE_OK) {
        return columns;
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *columnName = sqlite3_column_text(stmt, 1);
        if (columnName) {
            [columns addObject:[NSString stringWithUTF8String:(const char *)columnName]];
        }
    }
    sqlite3_finalize(stmt);
    return [columns copy];
}

static NSString *PDSOAuthClientDelimitedString(id value) {
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *items = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            if (![item isKindOfClass:[NSString class]]) {
                continue;
            }
            NSString *trimmed = [(NSString *)item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [items addObject:trimmed];
            }
        }
        return [items componentsJoinedByString:@" "];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return @"";
}

static NSArray<NSString *> *PDSOAuthClientDelimitedArray(id value) {
    NSString *string = PDSOAuthClientDelimitedString(value);
    if (string.length == 0) {
        return @[];
    }

    NSArray<NSString *> *parts = [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [items addObject:part];
        }
    }
    return [items copy];
}

@implementation PDSDatabase (OAuthClients)

- (nullable NSDictionary *)getClientWithID:(NSString *)clientID error:(NSError **)error {
    return [self getOAuthClientWithID:clientID error:error];
}

- (nullable NSDictionary *)getOAuthClientWithID:(NSString *)clientID error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSSet<NSString *> *columns = PDSOAuthClientColumns(self.db);
    BOOL hasResponseTypes = [columns containsObject:@"response_types"];
    NSString *sql = hasResponseTypes
        ? @"SELECT client_id, client_secret, redirect_uris, grant_types, response_types, scope FROM oauth_clients WHERE client_id = ?"
        : @"SELECT client_id, client_secret, redirect_uris, grant_types, scope FROM oauth_clients WHERE client_id = ?";

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
        dict[@"redirect_uris"] = PDSOAuthClientDelimitedArray(redirectUrisStr);

        id grants = [self valueFromStatement:stmt columnIndex:3];
        if (grants) dict[@"grant_types"] = PDSOAuthClientDelimitedString(grants);

        if (hasResponseTypes) {
            id responseTypes = [self valueFromStatement:stmt columnIndex:4];
            if (responseTypes) dict[@"response_types"] = PDSOAuthClientDelimitedString(responseTypes);
        }

        id scope = [self valueFromStatement:stmt columnIndex:(hasResponseTypes ? 5 : 4)];
        if (scope) dict[@"scope"] = scope;

        client = dict;
    }

    result = client;

    return;
    }];
    return result;
}

- (BOOL)createClient:(NSDictionary *)client error:(NSError **)error {
    return [self createOAuthClient:client error:error];
}

- (BOOL)createOAuthClient:(NSDictionary *)client error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSSet<NSString *> *availableColumns = PDSOAuthClientColumns(self.db);
    NSMutableArray<NSString *> *columns = [NSMutableArray arrayWithObjects:@"client_id", @"client_secret", @"redirect_uris", @"grant_types", nil];
    if ([availableColumns containsObject:@"response_types"]) {
        [columns addObject:@"response_types"];
    }
    if ([availableColumns containsObject:@"scope"]) {
        [columns addObject:@"scope"];
    }
    if ([availableColumns containsObject:@"created_at"]) {
        [columns addObject:@"created_at"];
    }

    NSMutableArray<NSString *> *placeholders = [NSMutableArray arrayWithCapacity:columns.count];
    for (NSUInteger i = 0; i < columns.count; i++) {
        [placeholders addObject:@"?"];
    }
    NSMutableArray<NSString *> *setClauses = [NSMutableArray arrayWithCapacity:columns.count];
    for (NSString *col in columns) {
        if (![col isEqualToString:@"client_id"]) {
            [setClauses addObject:[NSString stringWithFormat:@"%@=excluded.%@", col, col]];
        }
    }
    NSString *sql = [NSString stringWithFormat:@"INSERT INTO oauth_clients (%@) VALUES (%@) ON CONFLICT(client_id) DO UPDATE SET %@",
                     [columns componentsJoinedByString:@", "],
                     [placeholders componentsJoinedByString:@", "],
                     [setClauses componentsJoinedByString:@", "]];

    PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (error) *error = [self errorWithMessage:sqlite3_errmsg(self.db) code:PDSDatabaseErrorQueryFailed];
        result = NO;
        return;
    }

    int bindIndex = 1;
    for (NSString *column in columns) {
        id value = nil;
        if ([column isEqualToString:@"redirect_uris"] ||
            [column isEqualToString:@"grant_types"] ||
            [column isEqualToString:@"response_types"]) {
            value = PDSOAuthClientDelimitedString(client[column]);
        } else if ([column isEqualToString:@"created_at"]) {
            value = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        } else {
            value = client[column];
        }
        ATProtoDBBindValue(stmt, bindIndex++, value ?: [NSNull null]);
    }

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
    NSDictionary *client = @{
        @"client_id": @"test-client",
        @"client_secret": @"test-secret",
        @"redirect_uris": @[@"http://localhost/cb", @"http://localhost:2583/cb"],
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"scope": @"atproto"
    };

    NSError *deleteError = nil;
    [self deleteOAuthClientWithID:client[@"client_id"] error:&deleteError];
    return [self createClient:client error:error];
}

- (nullable NSArray<NSDictionary *> *)getAllOAuthClientsWithError:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSSet<NSString *> *columns = PDSOAuthClientColumns(self.db);
    BOOL hasResponseTypes = [columns containsObject:@"response_types"];
    NSString *sql = hasResponseTypes
        ? @"SELECT client_id, client_secret, redirect_uris, grant_types, response_types, scope FROM oauth_clients"
        : @"SELECT client_id, client_secret, redirect_uris, grant_types, scope FROM oauth_clients";

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
        dict[@"redirect_uris"] = PDSOAuthClientDelimitedArray(redirectUrisStr);

        id grants = [self valueFromStatement:stmt columnIndex:3];
        if (grants) dict[@"grant_types"] = PDSOAuthClientDelimitedString(grants);

        if (hasResponseTypes) {
            id responseTypes = [self valueFromStatement:stmt columnIndex:4];
            if (responseTypes) dict[@"response_types"] = PDSOAuthClientDelimitedString(responseTypes);
        }

        id scope = [self valueFromStatement:stmt columnIndex:(hasResponseTypes ? 5 : 4)];
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

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService+Stats.h"
#import "Debug/GZLogger.h"
#import "Core/ATProtoValidator.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"

@implementation PDSRecordService (Stats)

#pragma mark - Repository Statistics

- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error {
    __block NSDictionary *cached;
    dispatch_sync(self.statsCacheQueue, ^{
        cached = self.statsCacheByDid[did];
    });
    if (cached) return cached;

    if (![ATProtoValidator validateDID:did error:nil]) {
        return @{
            @"did": did ?: @"",
            @"collections": @[],
            @"recordCount": @0
        };
    }

    PDSActorStore *store = [self.databasePool storeForDid:did error:error];
    if (!store) {
        GZ_LOG_DB_ERROR(@"[PDSRecordService] Failed to get store for DID: %@", did);
        if (error) *error = [NSError errorWithDomain:@"com.atproto.pds.recordservice" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to get store"}];
        return nil;
    }
    
    __block NSMutableArray *results = [NSMutableArray array];
    __block NSInteger totalCount = 0;
    
    [store readWithBlock:^(id<PDSActorStoreReader> reader, NSError **blockError) {
        PDSActorStore *actorStore = (PDSActorStore *)reader;
        NSString *sql = @"SELECT collection, COUNT(*) as count FROM records GROUP BY collection ORDER BY collection";
        sqlite3_stmt *stmt = [actorStore prepareStatement:sql error:blockError];
        
        if (stmt) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *colName = (const char *)sqlite3_column_text(stmt, 0);
                int count = sqlite3_column_int(stmt, 1);
                
                if (colName) {
                    [results addObject:@{
                        @"collection": [NSString stringWithUTF8String:colName],
                        @"count": @(count)
                    }];
                    totalCount += count;
                }
            }
            [actorStore finalizeStatement:stmt];
        } else {
             if (blockError && *blockError) {
                GZ_LOG_DB_ERROR(@"[PDSRecordService] Failed to prepare stats statement: %@", *blockError);
             }
        }
    } error:error];
    
    if (error && *error) {
        return nil;
    }
    
    NSDictionary *result = @{
        @"did": did,
        @"collections": results,
        @"recordCount": @(totalCount)
    };

    dispatch_sync(self.statsCacheQueue, ^{
        self.statsCacheByDid[did] = result;
    });

    return result;
}

@end

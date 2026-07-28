// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSHealthCheck.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import <sqlite3.h>

@interface PDSHealthCheck ()
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@end

@implementation PDSHealthCheck

+ (instancetype)sharedInstance {
    static PDSHealthCheck *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSHealthCheck alloc] init];
    });
    return shared;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
    }
    return self;
}

- (void)configureWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    if (serviceDatabases) {
        _serviceDatabases = serviceDatabases;
    }
}

- (NSDictionary<NSString *, id> *)performHealthCheck {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSMutableArray *warnings = [NSMutableArray array];
    NSMutableArray *errors = [NSMutableArray array];
    
    result[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    result[@"status"] = @"healthy";
    
    NSError *integrityError = nil;
    PDSHealthStatus integrityStatus = [self checkDatabaseIntegrity:&integrityError];
    result[@"database_integrity"] = @(integrityStatus);
    
    if (integrityStatus == PDSHealthStatusCritical) {
        [errors addObject:integrityError.localizedDescription ?: @"Database integrity check failed"];
        result[@"status"] = @"critical";
    } else if (integrityStatus == PDSHealthStatusWarning) {
        [warnings addObject:integrityError.localizedDescription ?: @"Database integrity warning"];
        result[@"status"] = @"warning";
    }
    
    NSDictionary *tableSizes = [self getTableSizes];
    result[@"table_sizes"] = tableSizes;
    
    NSUInteger fragmentation = [self getFragmentationPercent];
    result[@"fragmentation_percent"] = @(fragmentation);
    
    if (fragmentation > 50) {
        [warnings addObject:[NSString stringWithFormat:@"High fragmentation: %lu%%", (unsigned long)fragmentation]];
    }
    
    NSDictionary *metrics = [self.serviceDatabases.servicePool collectMetrics];
    result[@"pool_metrics"] = metrics;
    
    NSUInteger openHandles = [metrics[@"open_file_handles"] unsignedIntegerValue];
    NSUInteger maxHandles = [metrics[@"max_size"] unsignedIntegerValue];
    result[@"file_handles"] = @{@"open": @(openHandles), @"max": @(maxHandles)};
    
    if (openHandles >= maxHandles * 0.9) {
        [warnings addObject:@"File handle pool approaching capacity"];
    }
    
    result[@"warnings"] = warnings;
    result[@"errors"] = errors;
    
    return result;
}

- (PDSHealthStatus)checkDatabaseIntegrity:(NSError **)error {
    PDSServiceDatabases *serviceDb = self.serviceDatabases;
    PDSActorStore *store = [serviceDb.servicePool storeForDid:@"__service__" error:nil];
    
    if (!store || !store.isOpen) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        }
        return PDSHealthStatusCritical;
    }
    
    // PRAGMA integrity_check streams its result set, so it runs on the raw
    // handle — but inside performWithSQLiteHandle:, which holds the database
    // queue for the duration and keeps the connection single-threaded.
    __block int result = SQLITE_OK;
    __block NSString *checkResult = nil;
    BOOL ran = [store.database performWithSQLiteHandle:^(sqlite3 *db) {
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        result = sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, NULL);
        if (result != SQLITE_OK) return;

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *text = (const char *)sqlite3_column_text(stmt, 0);
            if (text) checkResult = [NSString stringWithUTF8String:text];
        }
    }];

    if (!ran) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        }
        return PDSHealthStatusCritical;
    }

    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare integrity check"}];
        }
        return PDSHealthStatusCritical;
    }

    if ([checkResult isEqualToString:@"ok"]) {
        return PDSHealthStatusHealthy;
    } else if ([checkResult.lowercaseString containsString:@"ok"]) {
        return PDSHealthStatusWarning;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-2
                                    userInfo:@{NSLocalizedDescriptionKey: checkResult ?: @"Integrity check failed"}];
        }
        return PDSHealthStatusCritical;
    }
}

- (BOOL)checkForeignKeys:(NSError **)error {
    PDSServiceDatabases *serviceDb = self.serviceDatabases;
    PDSActorStore *store = [serviceDb.servicePool storeForDid:@"__service__" error:nil];
    
    if (!store) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        }
        return NO;
    }
    
    __block int result = SQLITE_OK;
    __block BOOL hasViolations = NO;
    BOOL ran = [store.database performWithSQLiteHandle:^(sqlite3 *db) {
        PDS_SQLITE_AUTORELEASE_STMT sqlite3_stmt *stmt = NULL;
        result = sqlite3_prepare_v2(db, "PRAGMA foreign_key_check", -1, &stmt, NULL);
        if (result != SQLITE_OK) return;

        hasViolations = (sqlite3_step(stmt) == SQLITE_ROW);
    }];

    if (!ran) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:-1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
        }
        return NO;
    }

    if (result != SQLITE_OK) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.pds.health"
                                        code:result
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to prepare foreign key check"}];
        }
        return NO;
    }

    return !hasViolations;
}

- (NSDictionary<NSString *, NSNumber *> *)getTableSizes {
    NSMutableDictionary *sizes = [NSMutableDictionary dictionary];
    
    PDSServiceDatabases *serviceDb = self.serviceDatabases;
    PDSActorStore *store = [serviceDb.servicePool storeForDid:@"__service__" error:nil];
    
    if (store && store.isOpen) {
        NSArray<NSDictionary *> *rows = [store.database executeParameterizedQuery:
            @"SELECT name, SUM(pages * page_size) as size FROM sqlite_master "
             "LEFT JOIN sqlite_dbpage USING(sqlite_dbpage.name) GROUP BY name"
            params:@[]
             error:nil];

        for (NSDictionary *row in rows) {
            NSString *name = row[@"name"];
            if (name.length > 0) {
                sizes[name] = @([row[@"size"] longLongValue]);
            }
        }
    }

    return sizes;
}

- (NSUInteger)getFragmentationPercent {
    PDSServiceDatabases *serviceDb = self.serviceDatabases;
    PDSActorStore *store = [serviceDb.servicePool storeForDid:@"__service__" error:nil];
    
    if (!store || !store.isOpen) {
        return 0;
    }
    
    NSArray<NSDictionary *> *rows = [store.database executeParameterizedQuery:
        @"SELECT SUM((leaf_pages - 1) * payload) / SUM(payload) AS fragmentation "
         "FROM dbstat WHERE name = 'accounts'"
        params:@[]
         error:nil];

    double fragmentation = [rows.firstObject[@"fragmentation"] doubleValue];
    return (NSUInteger)(fragmentation * 100);
}

- (NSDictionary<NSString *, id> *)collectMetrics {
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    
    metrics[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    
    PDSServiceDatabases *serviceDb = self.serviceDatabases;
    
    metrics[@"service_pool"] = [serviceDb.servicePool collectMetrics];
    metrics[@"did_cache_pool"] = [serviceDb.didCachePool collectMetrics];
    metrics[@"sequencer_pool"] = [self.serviceDatabases.sequencerPool collectMetrics];
    
    metrics[@"warnings"] = [self getWarnings];
    metrics[@"errors"] = [self getErrors];
    
    return metrics;
}

- (NSArray<NSString *> *)getWarnings {
    NSMutableArray *warnings = [NSMutableArray array];
    
    NSError *error = nil;
    PDSHealthStatus status = [self checkDatabaseIntegrity:&error];
    if (status == PDSHealthStatusWarning) {
        [warnings addObject:error.localizedDescription];
    }
    
    NSUInteger fragmentation = [self getFragmentationPercent];
    if (fragmentation > 30) {
        [warnings addObject:[NSString stringWithFormat:@"Database fragmentation: %lu%%", (unsigned long)fragmentation]];
    }
    
    return warnings;
}

- (NSArray<NSString *> *)getErrors {
    NSMutableArray *errors = [NSMutableArray array];
    
    NSError *error = nil;
    PDSHealthStatus status = [self checkDatabaseIntegrity:&error];
    if (status == PDSHealthStatusCritical) {
        [errors addObject:error.localizedDescription];
    }
    
    if (![self checkForeignKeys:nil]) {
        [errors addObject:@"Foreign key violations detected"];
    }
    
    return errors;
}

@end

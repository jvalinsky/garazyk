// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Beskid/AdminUI/BeskidAdminSnapshot.h"

#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidMetrics.h"
#import "Beskid/BeskidConfiguration.h"

NSString *GZBeskidAdminPasswordFromFile(NSString *path, NSError * _Nullable * _Nullable error) {
    NSString *password = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!password) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZBeskidAdminUI" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"Unable to read Beskid admin password file"
            }];
        }
        return nil;
    }
    password = [password stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if (password.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZBeskidAdminUI" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"Beskid admin password file is empty"
            }];
        }
        return nil;
    }
    return password;
}

@interface GZBeskidAdminSnapshot ()
@property(nonatomic, strong) BeskidDatabase *database;
@property(nonatomic, strong) BeskidMetrics *metrics;
@property(nonatomic, strong) BeskidConfiguration *configuration;
@end

@implementation GZBeskidAdminSnapshot

- (instancetype)initWithDatabase:(BeskidDatabase *)database
                         metrics:(BeskidMetrics *)metrics
                   configuration:(BeskidConfiguration *)configuration {
    self = [super init];
    if (self) {
        _database = database;
        _metrics = metrics;
        _configuration = configuration;
    }
    return self;
}

- (NSDictionary<NSString *, id> *)snapshot {
    NSDictionary *metricsSnapshot = [self.metrics snapshotDictionary];
    
    // health: degraded only when there are upstream requests with zero successes
    NSString *health = @"ok";
    NSArray *upstreams = metricsSnapshot[@"upstreams"];
    int64_t totalUpRequests = 0, totalUpSuccesses = 0;
    for (NSDictionary *up in upstreams) {
        totalUpRequests += [up[@"requests"] longLongValue];
        totalUpSuccesses += [up[@"successes"] longLongValue];
    }
    if (totalUpRequests > 0 && totalUpSuccesses == 0) {
        health = @"degraded";
    }
    
    // database storage bytes via PRAGMA (cheap in-connection call)
    int64_t storageBytes = [self.database storageBytes];
    
    return @{
        @"health": health,
        @"uptimeSeconds": metricsSnapshot[@"uptimeSeconds"],
        @"cache": @{
            @"record": metricsSnapshot[@"record"],
            @"identity": metricsSnapshot[@"identity"],
            @"overall": metricsSnapshot[@"overall"],
        },
        @"ttl": @{
            @"recordSeconds": @(self.configuration.cacheRecordTtlSeconds),
            @"identitySeconds": @(self.configuration.cacheIdentityTtlSeconds),
        },
        @"upstreams": metricsSnapshot[@"upstreams"],
        @"rateLimitRejects": metricsSnapshot[@"rateLimitRejects"],
        @"database": @{ @"storageBytes": @(storageBytes) },
    };
}

@end

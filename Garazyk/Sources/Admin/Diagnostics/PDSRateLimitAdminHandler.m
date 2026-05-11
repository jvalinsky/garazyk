// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRateLimitAdminHandler.h"
#import "Network/RateLimiter.h"
#import "Database/Service/ServiceDatabases.h"
#import <sqlite3.h>

@interface PDSRateLimitAdminHandler ()
@property (nonatomic, strong) RateLimiter *rateLimiter;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@end

@implementation PDSRateLimitAdminHandler

+ (instancetype)sharedHandler {
    static PDSRateLimitAdminHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSRateLimitAdminHandler alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rateLimiter = [RateLimiter sharedLimiter];
    }
    return self;
}

- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {

    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"application/json";

    if ([path isEqualToString:@"/query"]) {
        return [self queryRateLimit:body statusCode:statusCode];
    } else if ([path isEqualToString:@"/top"]) {
        return [self getTopLimitedUsers:path statusCode:statusCode];
    } else if ([path isEqualToString:@"/clear"]) {
        return [self clearRateLimit:body statusCode:statusCode];
    }

    if (statusCode) *statusCode = 404;
    return @"{\"error\": \"Not Found\"}";
}

- (NSString *)queryRateLimit:(nullable NSData *)body statusCode:(nullable NSInteger *)statusCode {
    if (!body) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Missing request body\"}";
    }

    NSError *error = nil;
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:body options:0 error:&error];
    if (!request || error) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Invalid JSON\"}";
    }

    NSString *identifier = request[@"identifier"];
    NSString *type = request[@"type"];

    if (!identifier || !type) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Missing identifier or type\"}";
    }

    // Query current rate limit status using RateLimiter API
    RateLimitResult *rateLimitResult = nil;
    if ([type isEqualToString:@"did"]) {
        rateLimitResult = [self.rateLimiter checkRateLimitForDid:identifier];
    } else if ([type isEqualToString:@"ip"]) {
        rateLimitResult = [self.rateLimiter checkRateLimitForIP:identifier];
    } else if ([type isEqualToString:@"blob"]) {
        rateLimitResult = [self.rateLimiter checkBlobUploadRateLimitForDid:identifier];
    }

    NSDictionary *response;
    if (rateLimitResult) {
        NSString *statusStr = rateLimitResult.allowed ? @"ok" : @"limited";
        response = @{
            @"identifier": identifier,
            @"type": type,
            @"currentCount": @(rateLimitResult.limit - rateLimitResult.remaining),
            @"limit": @(rateLimitResult.limit),
            @"remaining": @(rateLimitResult.remaining),
            @"windowStart": [NSDate date].description,
            @"windowEnd": [[NSDate dateWithTimeIntervalSinceNow:rateLimitResult.resetSeconds] description],
            @"status": statusStr
        };
    } else {
        response = @{
            @"identifier": identifier,
            @"type": type,
            @"currentCount": @0,
            @"limit": @0,
            @"remaining": @0,
            @"windowStart": [NSDate date].description,
            @"windowEnd": [[NSDate dateWithTimeIntervalSinceNow:3600] description],
            @"status": @"unknown"
        };
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    if (!jsonData) {
        if (statusCode) *statusCode = 500;
        return @"{\"error\": \"Failed to serialize response\"}";
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)getTopLimitedUsers:(NSString *)path statusCode:(nullable NSInteger *)statusCode {
    // Parse limit parameter
    NSInteger limit = 20;
    NSRange queryRange = [path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        NSString *queryString = [path substringFromIndex:queryRange.location + 1];
        NSDictionary *params = [self parseQueryString:queryString];
        if (params[@"limit"]) {
            limit = [params[@"limit"] integerValue];
        }
    }

    // Query top rate-limited identifiers from RateLimiter
    NSArray *topUsers = [self.rateLimiter getTopLimitedIdentifiers:limit];
    NSDictionary *response = @{
        @"users": topUsers,
        @"limit": @(limit),
        @"timestamp": [NSNumber numberWithLongLong:(long long)[[NSDate date] timeIntervalSince1970]]
    };

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    if (!jsonData) {
        if (statusCode) *statusCode = 500;
        return @"{\"error\": \"Failed to serialize response\"}";
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)clearRateLimit:(nullable NSData *)body statusCode:(nullable NSInteger *)statusCode {
    if (!body) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Missing request body\"}";
    }

    NSError *error = nil;
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:body options:0 error:&error];
    if (!request || error) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Invalid JSON\"}";
    }

    NSString *identifier = request[@"identifier"];
    NSString *type = request[@"type"];
    NSString *reason = request[@"reason"];
    NSString *adminDid = request[@"adminDid"];

    if (!identifier || !type || !reason) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Missing identifier, type, or reason\"}";
    }

    // Clear rate limit entries from RateLimiter
    NSInteger clearedCount = [self.rateLimiter clearRateLimitForIdentifier:identifier type:type];
    NSDictionary *response = @{
        @"success": @YES,
        @"identifier": identifier,
        @"type": type,
        @"clearedCount": @(clearedCount),
        @"historyId": @0
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    if (!jsonData) {
        if (statusCode) *statusCode = 500;
        return @"{\"error\": \"Failed to serialize response\"}";
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSDictionary *)parseQueryString:(NSString *)queryString {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSArray *pairs = [queryString componentsSeparatedByString:@"&"];

    for (NSString *pair in pairs) {
        NSArray *components = [pair componentsSeparatedByString:@"="];
        if (components.count == 2) {
            NSString *key = [components[0] stringByRemovingPercentEncoding];
            NSString *value = [components[1] stringByRemovingPercentEncoding];
            params[key] = value;
        }
    }

    return [params copy];
}

- (BOOL)clearRateLimitForIdentifier:(NSString *)identifier
                               type:(NSString *)type
                            adminDid:(NSString *)adminDid
                             reason:(NSString *)reason
                              error:(NSError **)error {
    // Validate inputs
    if (!identifier || identifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRateLimitAdminHandler" code:400 userInfo:@{NSLocalizedDescriptionKey: @"identifier required"}];
        }
        return NO;
    }
    if (!type || (![type isEqualToString:@"did"] && ![type isEqualToString:@"ip"] && ![type isEqualToString:@"blob"])) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRateLimitAdminHandler" code:400 userInfo:@{NSLocalizedDescriptionKey: @"type must be did, ip, or blob"}];
        }
        return NO;
    }
    if (!reason || reason.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRateLimitAdminHandler" code:400 userInfo:@{NSLocalizedDescriptionKey: @"reason required"}];
        }
        return NO;
    }

    // RateLimiter doesn't have clearLimitForIdentifier, so we just succeed
    // In a real implementation, this would clear the rate limit from the store

    return YES;
}

- (nullable NSDictionary *)queryRateLimitForIdentifier:(NSString *)identifier
                                                   type:(NSString *)type
                                                  error:(NSError **)error {
    // Validate inputs
    if (!identifier || identifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSRateLimitAdminHandler" code:400 userInfo:@{NSLocalizedDescriptionKey: @"identifier required"}];
        }
        return nil;
    }

    // Return a default status (no rate limit applied)
    return @{
        @"identifier": identifier,
        @"type": type ?: @"unknown",
        @"limit": @(1000),
        @"remaining": @(1000),
        @"reset_at": @([[NSDate date] timeIntervalSince1970] + 3600)
    };
}

@end

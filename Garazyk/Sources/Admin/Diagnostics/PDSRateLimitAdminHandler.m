#import "PDSRateLimitAdminHandler.h"
#import "Network/RateLimiter.h"
#import "Database/Service/ServiceDatabases.h"
#import "Foundation/NSError+JSON.h"
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
        // Get service databases singleton - adjust as needed based on your codebase
        // _serviceDatabases = [PDSServiceDatabases sharedDatabases];
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

    // Query current rate limit status
    // TODO: Use RateLimiter API to get current status
    NSDictionary *response = @{
        @"identifier": identifier,
        @"type": type,
        @"currentCount": @0,
        @"limit": @5000,
        @"remaining": @5000,
        @"windowStart": [NSDate date].description,
        @"windowEnd": [[NSDate dateWithTimeIntervalSinceNow:3600] description],
        @"status": @"ok"
    };

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

    // TODO: Query rate_limits table for top users
    NSDictionary *response = @{
        @"users": @[],
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

    // TODO: Delete from rate_limits table and insert into rate_limit_history
    NSDictionary *response = @{
        @"success": @YES,
        @"identifier": identifier,
        @"type": type,
        @"clearedCount": @0,
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

@end

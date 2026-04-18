#import "PDSSequencerHealthHandler.h"
#import "Analytics/PDSSequencerAnalyticsCollector.h"
#import "Foundation/NSError+JSON.h"

@interface PDSSequencerHealthHandler ()
@property (nonatomic, strong) PDSSequencerAnalyticsCollector *analyticsCollector;
@end

@implementation PDSSequencerHealthHandler

+ (instancetype)sharedHandler {
    static PDSSequencerHealthHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSSequencerHealthHandler alloc] init];
    });
    return shared;
}

- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {

    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"application/json";

    if ([path isEqualToString:@"/stats"]) {
        return [self getSequencerStats];
    } else if ([path hasPrefix:@"/history"]) {
        return [self getSequencerHistory:path];
    }

    if (statusCode) *statusCode = 404;
    return @"{\"error\": \"Not Found\"}";
}

- (NSString *)getSequencerStats {
    // TODO: Wire in analytics collector
    NSDictionary *snapshot = @{
        @"currentSeq": @0,
        @"eventsPerSecond": @0.0,
        @"subscriberCount": @0,
        @"backpressureWarnings": @0,
        @"backpressureCritical": @0,
        @"queueOverflows": @0,
        @"eventTypes": @{},
        @"healthStatus": @"unknown"
    };

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
    if (!jsonData) {
        return @"{\"error\": \"Failed to serialize response\"}";
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)getSequencerHistory:(NSString *)path {
    // Parse hours parameter from query string
    NSInteger hours = 24;
    NSRange queryRange = [path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        NSString *queryString = [path substringFromIndex:queryRange.location + 1];
        NSDictionary *params = [self parseQueryString:queryString];
        if (params[@"hours"]) {
            hours = [params[@"hours"] integerValue];
        }
    }

    // TODO: Wire in analytics collector to retrieve historical data
    NSDictionary *response = @{
        @"dataPoints": @[],
        @"hours": @(hours),
        @"startTime": [NSNumber numberWithLongLong:(long long)[[NSDate date] timeIntervalSince1970] - (hours * 3600]
    };

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    if (!jsonData) {
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

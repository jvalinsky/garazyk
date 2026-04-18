#import "PDSBlobAuditHandler.h"
#import "BlobAudit/PDSBlobAuditManager.h"
#import "Foundation/NSError+JSON.h"

@interface PDSBlobAuditHandler ()
@property (nonatomic, strong) PDSBlobAuditManager *auditManager;
@end

@implementation PDSBlobAuditHandler

+ (instancetype)sharedHandler {
    static PDSBlobAuditHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSBlobAuditHandler alloc] init];
    });
    return shared;
}

- (PDSBlobAuditManager *)auditManager {
    if (!_auditManager) {
        // Lazy initialization - would be set from PDSApplication or injected
        // For now, this placeholder will be replaced by proper dependency injection
        // when integrated into PDSApplication
    }
    return _auditManager;
}

- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {

    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"application/json";

    if ([path isEqualToString:@"/audit"]) {
        return [self startAudit:body statusCode:statusCode];
    } else if ([path hasPrefix:@"/status"]) {
        return [self getJobStatus:path statusCode:statusCode];
    }

    if (statusCode) *statusCode = 404;
    return @"{\"error\": \"Not Found\"}";
}

- (NSString *)startAudit:(nullable NSData *)body statusCode:(nullable NSInteger *)statusCode {
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

    NSString *auditType = request[@"auditType"];
    BOOL dryRun = [request[@"dryRun"] boolValue];

    if (!auditType) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Missing auditType\"}";
    }

    // Start audit job via manager
    NSString *jobId = [self.auditManager startAuditWithType:auditType dryRun:dryRun];
    if (!jobId) {
        if (statusCode) *statusCode = 500;
        return @"{\"error\": \"Failed to start audit job\"}";
    }

    NSDictionary *response = @{
        @"jobId": jobId,
        @"status": @"pending",
        @"auditType": auditType,
        @"dryRun": @(dryRun)
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    if (!jsonData) {
        if (statusCode) *statusCode = 500;
        return @"{\"error\": \"Failed to serialize response\"}";
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)getJobStatus:(NSString *)path statusCode:(nullable NSInteger *)statusCode {
    // Parse jobId from query string
    NSString *jobId = nil;
    NSRange queryRange = [path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        NSString *queryString = [path substringFromIndex:queryRange.location + 1];
        NSDictionary *params = [self parseQueryString:queryString];
        jobId = params[@"jobId"];
    }

    if (!jobId) {
        if (statusCode) *statusCode = 400;
        return @"{\"error\": \"Missing jobId parameter\"}";
    }

    // Query job status from audit manager
    NSDictionary *jobStatus = [self.auditManager jobStatusForId:jobId];
    if (!jobStatus) {
        if (statusCode) *statusCode = 404;
        return @"{\"error\": \"Job not found\"}";
    }

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jobStatus options:0 error:&error];
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

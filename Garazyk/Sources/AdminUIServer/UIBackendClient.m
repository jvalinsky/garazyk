#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"

@interface UIBackendClient ()

@property(nonatomic, strong) UIServiceConfig *configuration;

@end

@implementation UIBackendClient

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
    }
    return self;
}

- (NSDictionary *)fetchServiceOverview {
    NSMutableArray<NSDictionary *> *services = [NSMutableArray array];

    [services addObject:[self probeServiceNamed:@"pds"
                                        baseURL:self.configuration.pdsBaseURL
                                      xrpcPath:@"/xrpc/com.atproto.server.describeServer"
                                  bearerToken:self.configuration.pdsAdminToken]];
    [services addObject:[self probeServiceNamed:@"plc"
                                        baseURL:self.configuration.plcBaseURL
                                      xrpcPath:nil
                                  bearerToken:self.configuration.plcAdminToken]];
    [services addObject:[self probeServiceNamed:@"relay"
                                        baseURL:self.configuration.relayBaseURL
                                      xrpcPath:@"/xrpc/com.atproto.sync.listRepos?limit=1"
                                  bearerToken:self.configuration.relayAdminToken]];
    [services addObject:[self probeServiceNamed:@"appview"
                                        baseURL:self.configuration.appViewBaseURL
                                      xrpcPath:@"/xrpc/app.bsky.feed.getTimeline?limit=1"
                                  bearerToken:self.configuration.appViewAdminToken]];
    [services addObject:[self probeServiceNamed:@"chat"
                                        baseURL:self.configuration.chatBaseURL
                                      xrpcPath:@"/xrpc/chat.bsky.convo.listConvos?limit=1"
                                  bearerToken:self.configuration.chatAdminToken]];

    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    NSString *generatedAt = [formatter stringFromDate:[NSDate date]];
    return @{@"services": services, @"generatedAt": generatedAt ?: @""};
}

- (NSDictionary *)searchAccountsWithQuery:(NSString *)query {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.searchAccounts"
                              queryItems:@{
                                @"limit": @"25",
                                @"email": query.length > 0 ? query : @""
                              }
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                      method:@"GET"
                                                        body:nil
                                                 bearerToken:self.configuration.pdsAdminToken
                                                  statusCode:&status
                                                       error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"pds_search_failed",
                 @"status": @(status),
                 @"message": error.localizedDescription ?: @"Search request failed",
                 @"accounts": @[]};
    }
    NSMutableDictionary *result = [response mutableCopy];
    if (![result[@"accounts"] isKindOfClass:[NSArray class]]) {
        result[@"accounts"] = @[];
    }
    return [result copy];
}

- (NSDictionary *)fetchInviteCodes {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.getInviteCodes"
                              queryItems:@{@"limit": @"25"}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                      method:@"GET"
                                                        body:nil
                                                 bearerToken:self.configuration.pdsAdminToken
                                                  statusCode:&status
                                                       error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"pds_invites_failed",
                 @"status": @(status),
                 @"message": error.localizedDescription ?: @"Invite request failed",
                 @"codes": @[]};
    }
    NSMutableDictionary *result = [response mutableCopy];
    if (![result[@"codes"] isKindOfClass:[NSArray class]]) {
        result[@"codes"] = @[];
    }
    return [result copy];
}

- (NSDictionary *)disableInvitesForAccount:(NSString *)account {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @{@"error": @"invalid_account", @"message": @"Account DID is required"};
    }

    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.disableAccountInvites"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"account": trimmed};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                      method:@"POST"
                                                        body:body
                                                 bearerToken:self.configuration.pdsAdminToken
                                                  statusCode:&status
                                                       error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"disable_invites_failed",
                 @"status": @(status),
                 @"message": error.localizedDescription ?: @"Disable invites failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)probeServiceNamed:(NSString *)name
                             baseURL:(NSURL *)baseURL
                           xrpcPath:(NSString *)xrpcPath
                       bearerToken:(NSString *)token {
    NSInteger rootStatus = 0;
    NSError *rootError = nil;
    NSString *banner = [self performTextRequestWithURL:[self URLByAppendingPath:@"/"
                                                                     queryItems:nil
                                                                        baseURL:baseURL]
                                                 method:@"GET"
                                            bearerToken:nil
                                             statusCode:&rootStatus
                                                  error:&rootError];

    NSInteger xrpcStatus = 0;
    NSError *xrpcError = nil;
    if (xrpcPath.length > 0) {
        NSURL *xrpcURL = [self URLByPathWithQuery:xrpcPath baseURL:baseURL];
        (void)[self performJSONRequestWithURL:xrpcURL
                                       method:@"GET"
                                         body:nil
                                  bearerToken:token
                                   statusCode:&xrpcStatus
                                        error:&xrpcError];
    }

    BOOL connected = (xrpcPath.length > 0) ? (xrpcStatus >= 200 && xrpcStatus < 300)
                                           : (rootStatus >= 200 && rootStatus < 300);

    NSString *version = [self versionFromBanner:banner] ?: @"unknown";
    NSString *detail = connected ? @"ok" : (xrpcError.localizedDescription ?: rootError.localizedDescription ?: @"unreachable");
    return @{
        @"name": name ?: @"service",
        @"connected": @(connected),
        @"version": version,
        @"rootStatus": @(rootStatus),
        @"xrpcStatus": @(xrpcStatus),
        @"detail": detail ?: @""
    };
}

- (NSString *)versionFromBanner:(NSString *)banner {
    NSString *trimmed = [banner stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (parts.count < 2) {
        return nil;
    }
    NSString *version = parts.lastObject;
    return version.length > 0 ? version : nil;
}

- (NSURL *)URLByAppendingPath:(NSString *)path
                  queryItems:(NSDictionary<NSString *, NSString *> *)items
                     baseURL:(NSURL *)baseURL {
    NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    NSString *basePath = components.path ?: @"";
    if (basePath.length == 0 || [basePath isEqualToString:@"/"]) {
        components.path = path ?: @"/";
    } else {
        NSString *joined = [basePath stringByAppendingPathComponent:[path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];
        components.path = [joined hasPrefix:@"/"] ? joined : [@"/" stringByAppendingString:joined];
    }

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    for (NSString *key in items) {
        NSString *value = items[key];
        if (value.length > 0) {
            [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:value]];
        }
    }
    components.queryItems = queryItems.count > 0 ? queryItems : nil;
    return components.URL;
}

- (NSURL *)URLByPathWithQuery:(NSString *)pathWithQuery baseURL:(NSURL *)baseURL {
    NSString *path = pathWithQuery ?: @"";
    NSString *query = nil;
    NSRange queryRange = [path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        query = [path substringFromIndex:queryRange.location + 1];
        path = [path substringToIndex:queryRange.location];
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    NSString *basePath = components.path ?: @"";
    if (basePath.length == 0 || [basePath isEqualToString:@"/"]) {
        components.path = path;
    } else {
        NSString *joined = [basePath stringByAppendingPathComponent:[path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];
        components.path = [joined hasPrefix:@"/"] ? joined : [@"/" stringByAppendingString:joined];
    }
    components.percentEncodedQuery = query;
    return components.URL;
}

- (NSDictionary *)performJSONRequestWithURL:(NSURL *)url
                                     method:(NSString *)method
                                       body:(NSDictionary *)body
                                bearerToken:(NSString *)token
                                 statusCode:(NSInteger *)statusCode
                                      error:(NSError **)error {
    NSData *bodyData = nil;
    if (body) {
        NSError *encodeError = nil;
        bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encodeError];
        if (!bodyData) {
            if (statusCode) *statusCode = 0;
            if (error) *error = encodeError;
            return nil;
        }
    }

    NSData *responseData = [self performRequestWithURL:url
                                                method:method
                                                  body:bodyData
                                           contentType:body ? @"application/json" : nil
                                            bearerToken:token
                                             statusCode:statusCode
                                                  error:error];
    if (!responseData || responseData.length == 0) {
        return @{};
    }

    NSError *jsonError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&jsonError];
    if (jsonError) {
        if (error) *error = jsonError;
        return nil;
    }
    if ([parsed isKindOfClass:[NSDictionary class]]) {
        return parsed;
    }
    if ([parsed isKindOfClass:[NSArray class]]) {
        return @{@"items": parsed};
    }
    return @{};
}

- (NSString *)performTextRequestWithURL:(NSURL *)url
                                 method:(NSString *)method
                            bearerToken:(NSString *)token
                             statusCode:(NSInteger *)statusCode
                                  error:(NSError **)error {
    NSData *data = [self performRequestWithURL:url
                                        method:method
                                          body:nil
                                   contentType:nil
                                    bearerToken:token
                                     statusCode:statusCode
                                          error:error];
    if (!data) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSData *)performRequestWithURL:(NSURL *)url
                           method:(NSString *)method
                             body:(NSData *)body
                      contentType:(NSString *)contentType
                       bearerToken:(NSString *)token
                        statusCode:(NSInteger *)statusCode
                             error:(NSError **)error {
    if (!url) {
        if (statusCode) *statusCode = 0;
        if (error) {
            *error = [NSError errorWithDomain:@"UIBackendClient"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing URL"}];
        }
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method ?: @"GET";
    request.timeoutInterval = 10.0;
    if (body.length > 0) {
        request.HTTPBody = body;
    }
    if (contentType.length > 0) {
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    }
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    __block NSData *responseData = nil;
    __block NSInteger localStatus = 0;
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                  completionHandler:^(NSData *data,
                                                                                      NSURLResponse *response,
                                                                                      NSError *taskError) {
        if (taskError) {
            localError = taskError;
        }
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            localStatus = ((NSHTTPURLResponse *)response).statusCode;
        }
        responseData = data;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];

    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)));
    if (waitResult != 0) {
        [task cancel];
        localError = [NSError errorWithDomain:@"UIBackendClient"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
        localStatus = 0;
    }

    if (statusCode) *statusCode = localStatus;
    if (localError && error) *error = localError;
    return responseData;
}

@end


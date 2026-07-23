// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Debug/GZLogger.h"
#import "Network/ATProtoSafeHTTPClient.h"

static NSString *UIBackendEscapedPathSegment(NSString *segment) {
    if (![segment isKindOfClass:[NSString class]]) {
        return @"";
    }
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    return [segment stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

@implementation UIBackendClient

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration {
    return [self initWithConfiguration:configuration httpClient:nil];
}

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration
                           httpClient:(nullable ATProtoSafeHTTPClient *)httpClient {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _httpClient = httpClient;
    }
    return self;
}

#pragma mark - Private Helper Methods

- (NSArray<NSDictionary *> *)serviceProbeSpecifications {
    return @[
        @{@"name": @"pds", @"baseURL": self.configuration.pdsBaseURL ?: [NSNull null], @"xrpcPath": @"/xrpc/com.atproto.server.describeServer", @"token": self.configuration.pdsAdminToken ?: [NSNull null]},
        @{@"name": @"plc", @"baseURL": self.configuration.plcBaseURL ?: [NSNull null], @"xrpcPath": @"/_health", @"token": self.configuration.plcAdminToken ?: [NSNull null]},
        @{@"name": @"relay", @"baseURL": self.configuration.relayBaseURL ?: [NSNull null], @"xrpcPath": @"/api/relay/health", @"token": self.configuration.relayAdminToken ?: [NSNull null]},
        @{@"name": @"appview", @"baseURL": self.configuration.appViewBaseURL ?: [NSNull null], @"xrpcPath": @"/admin/ingest/health", @"token": self.configuration.appViewAdminToken ?: [NSNull null]},
        @{@"name": @"chat", @"baseURL": self.configuration.chatBaseURL ?: [NSNull null], @"xrpcPath": @"/_health", @"token": self.configuration.chatAdminToken ?: [NSNull null]},
        @{@"name": @"video", @"baseURL": self.configuration.videoBaseURL ?: [NSNull null], @"xrpcPath": @"/_health", @"token": self.configuration.videoAdminToken ?: [NSNull null]}
    ];
}

- (NSString *)pathWithSegments:(NSArray<NSString *> *)segments {
    NSMutableArray<NSString *> *escaped = [NSMutableArray arrayWithCapacity:segments.count];
    for (NSString *segment in segments) {
        [escaped addObject:UIBackendEscapedPathSegment(segment)];
    }
    return [@"/" stringByAppendingString:[escaped componentsJoinedByString:@"/"]];
}

- (NSURL *)URLByAppendingPath:(NSString *)path queryItems:(id)queryItems baseURL:(NSURL *)baseURL {
    NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
    NSString *basePath = components.percentEncodedPath ?: @"";
    NSString *appendPath = path ?: @"";
    while ([basePath hasSuffix:@"/"] && basePath.length > 1) {
        basePath = [basePath substringToIndex:basePath.length - 1];
    }
    while ([appendPath hasPrefix:@"/"]) {
        appendPath = [appendPath substringFromIndex:1];
    }
    NSString *combinedPath = nil;
    if (basePath.length == 0 || [basePath isEqualToString:@"/"]) {
        combinedPath = appendPath.length > 0 ? [@"/" stringByAppendingString:appendPath] : @"/";
    } else {
        combinedPath = appendPath.length > 0 ? [basePath stringByAppendingFormat:@"/%@", appendPath] : basePath;
    }
    components.percentEncodedPath = combinedPath;

    if (!queryItems) return components.URL ?: baseURL;

    if ([queryItems isKindOfClass:[NSDictionary class]]) {
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
        NSDictionary *dict = (NSDictionary *)queryItems;
        NSArray<NSString *> *keys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *key in keys) {
            id value = dict[key];
            if ([value isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)value) {
                    NSString *valueStr = [item isKindOfClass:[NSString class]] ? item : [item description];
                    [items addObject:[NSURLQueryItem queryItemWithName:key value:valueStr]];
                }
            } else {
                NSString *valueStr = [value isKindOfClass:[NSString class]] ? value : [value description];
                [items addObject:[NSURLQueryItem queryItemWithName:key value:valueStr]];
            }
        }
        components.queryItems = items;
    } else if ([queryItems isKindOfClass:[NSArray class]]) {
        components.queryItems = (NSArray<NSURLQueryItem *> *)queryItems;
    }

    return components.URL ?: baseURL;
}

- (NSDictionary *)performPDSRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSDictionary *)body statusCode:(NSInteger *)statusCode error:(NSError **)error {
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                     method:method
                                                       body:body
                                                  bearerToken:self.configuration.pdsAdminToken
                                                   statusCode:statusCode
                                                        error:error];
    // Auto-refresh on 401 if we have a PDS admin password configured
    if (statusCode && *statusCode == 401 && self.configuration.pdsAdminPassword.length > 0) {
        if ([self refreshPDSAdminToken]) {
            response = [self performJSONRequestWithURL:url
                                                method:method
                                                  body:body
                                             bearerToken:self.configuration.pdsAdminToken
                                              statusCode:statusCode
                                                   error:error];
        }
    }
    return response;
}

- (NSDictionary *)performJSONRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSDictionary *)body bearerToken:(nullable NSString *)token statusCode:(NSInteger *)statusCode error:(NSError **)error {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = 30.0;

    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    if (token && token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    if (body) {
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
        if (!bodyData) {
            return @{@"error": @"json_encoding_failed"};
        }
        request.HTTPBody = bodyData;
    }

    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSData *responseData = nil;
    __block NSError *requestError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    ATProtoSafeHTTPClient *client = self.httpClient ?: [ATProtoSafeHTTPClient sharedClient];
    [client performSafeDataTaskWithRequest:request options:[ATProtoSafeHTTPClientOptions defaultOptions] completion:^(NSData *data, NSURLResponse *response, NSError *err) {
        responseData = data;
        httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        requestError = err;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35.0 * NSEC_PER_SEC)));

    if (statusCode && httpResponse) {
        *statusCode = httpResponse.statusCode;
    } else if (statusCode) {
        *statusCode = 0;
    }

    if (error) {
        *error = requestError;
    }

    if (requestError) {
        return @{@"error": @"request_failed", @"message": requestError.localizedDescription ?: @"Request failed"};
    }

    if (!responseData || responseData.length == 0) {
        return @{};
    }

    id json = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingAllowFragments error:nil];
    // Strip NSNull values from JSON so render methods never encounter them.
    // NSJSONSerialization converts JSON null -> [NSNull null], which crashes
    // when NSString methods like -length or -stringByReplacingOccurrencesOfString:
    // are called on it. Replacing with nil makes the ?: @"" fallbacks work.
    static id (^UIStripNull)(id) = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIStripNull = ^id(id obj) {
            if ([obj isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
                    id stripped = UIStripNull(val);
                    if (stripped) out[key] = stripped;
                }];
                return out;
            } else if ([obj isKindOfClass:[NSArray class]]) {
                NSMutableArray *out = [NSMutableArray array];
                for (id item in (NSArray *)obj) {
                    id stripped = UIStripNull(item);
                    if (stripped) [out addObject:stripped];
                }
                return out;
            } else if ([obj isKindOfClass:[NSNull class]]) {
                return (id)nil;
            }
            return obj;
        };
    });
    id stripped = UIStripNull(json);
    // Ensure we always return an NSDictionary — callers expect dict subscripting.
    // If the server returned a bare JSON array, wrap it as {"items": [...]}.
    if ([stripped isKindOfClass:[NSArray class]]) {
        return @{@"items": stripped};
    }
    if ([stripped isKindOfClass:[NSDictionary class]]) {
        return stripped;
    }
    return @{};
}

- (NSData *)performStringRequestWithURL:(NSURL *)url method:(NSString *)method bearerToken:(nullable NSString *)token statusCode:(NSInteger *)statusCode error:(NSError **)error {
    return [self performRequestWithURL:url method:method body:nil contentType:nil bearerToken:token statusCode:statusCode error:error];
}

- (NSData *)performRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSData *)body contentType:(nullable NSString *)contentType bearerToken:(nullable NSString *)token statusCode:(NSInteger *)statusCode error:(NSError **)error {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = 30.0;

    if (contentType) {
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    }

    if (token && token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    if (body) {
        request.HTTPBody = body;
    }

    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSData *responseData = nil;
    __block NSError *requestError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    ATProtoSafeHTTPClient *client = self.httpClient ?: [ATProtoSafeHTTPClient sharedClient];
    [client performSafeDataTaskWithRequest:request options:[ATProtoSafeHTTPClientOptions defaultOptions] completion:^(NSData *data, NSURLResponse *response, NSError *err) {
        responseData = data;
        httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        requestError = err;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35.0 * NSEC_PER_SEC)));

    if (statusCode && httpResponse) {
        *statusCode = httpResponse.statusCode;
    } else if (statusCode) {
        *statusCode = 0;
    }

    if (error) {
        *error = requestError;
    }

    return responseData;
}

- (NSDictionary *)probeServiceNamed:(NSString *)name
                           baseURL:(NSURL *)baseURL
                         xrpcPath:(nullable NSString *)xrpcPath
                     bearerToken:(nullable NSString *)token {
    if (!baseURL) {
        return @{@"name": name, @"status": @"offline", @"url": @"(not configured)"};
    }

    NSTimeInterval start = [[NSDate date] timeIntervalSince1970];
    NSInteger status = 0;
    NSError *error = nil;
    
    NSString *probePath = xrpcPath ?: @"/xrpc/_health";
    NSURL *probeURL = [self URLByAppendingPath:probePath queryItems:nil baseURL:baseURL];
    
    NSData *data = [self performRequestWithURL:probeURL method:@"GET" body:nil contentType:nil bearerToken:token statusCode:&status error:&error];
    NSTimeInterval latency = ([[NSDate date] timeIntervalSince1970] - start) * 1000.0;

    if (status >= 200 && status < 300) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"name"] = name ?: @"unknown";
        result[@"status"] = @"online";
        result[@"url"] = [baseURL absoluteString] ?: @"";
        result[@"latency_ms"] = [NSString stringWithFormat:@"%.0f", latency];
        
        if (data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"version"]) {
                result[@"version"] = [json[@"version"] description];
            } else {
                // Handle plain text responses (e.g. "syrena 1.0.0")
                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (text.length > 0) {
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+\\.\\d+\\.\\d+)" options:0 error:nil];
                    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
                    if (match) {
                        result[@"version"] = [text substringWithRange:match.range];
                    }
                }
            }
        }
        return [result copy];
    } else {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"name"] = name ?: @"unknown";
        result[@"status"] = status == 0 ? @"offline" : @"error";
        result[@"url"] = [baseURL absoluteString] ?: @"";
        result[@"error"] = error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld", (long)status];
        return [result copy];
    }
}

- (NSInteger)probeURL:(NSURL *)url withToken:(nullable NSString *)token {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 5.0;

    if (token && token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    __block NSInteger statusCode = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    ATProtoSafeHTTPClient *client = self.httpClient ?: [ATProtoSafeHTTPClient sharedClient];
    [client performSafeDataTaskWithRequest:request options:[ATProtoSafeHTTPClientOptions defaultOptions] completion:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = ((NSHTTPURLResponse *)response).statusCode;
        }
        (void)data;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)));
    return statusCode;
}

@end
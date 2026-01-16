#import "Federation/FederationClient.h"
#import "Core/DID.h"
#import <os/log.h>

NSErrorDomain const FederationErrorDomain = @"com.atproto.federation";

@implementation FederationClient {
    os_log_t _log;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _log = os_log_create("com.atproto.federation", "FederationClient");

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];

        _didResolver = [[DIDResolver alloc] init];
    }
    return self;
}

- (void)forwardXrpcRequest:(NSString *)method
                parameters:(nullable NSDictionary *)parameters
                       did:(NSString *)did
                completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion {

    if (!completion) return;

    // Resolve the DID to find the PDS endpoint
    NSDictionary *atprotoData = [(DIDResolver *)self.didResolver resolveAtprotoDataForDID:did error:nil];
    if (!atprotoData || !atprotoData[@"pds"]) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorDIDResolutionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to resolve PDS endpoint for DID"}];
        completion(nil, error);
        return;
    }

    NSString *pdsEndpoint = atprotoData[@"pds"];
    if (![pdsEndpoint hasPrefix:@"http"]) {
        pdsEndpoint = [NSString stringWithFormat:@"https://%@", pdsEndpoint];
    }

    // Construct the XRPC URL
    NSString *xrpcPath = [NSString stringWithFormat:@"/xrpc/%@", method];
    NSString *urlString = [NSString stringWithFormat:@"%@%@", pdsEndpoint, xrpcPath];

    // Add query parameters for GET requests
    if (parameters && [self isGetMethod:method]) {
        NSMutableArray<NSString *> *queryParts = [NSMutableArray array];
        for (NSString *key in parameters) {
            NSString *value = parameters[key];
            if ([value isKindOfClass:[NSString class]]) {
                NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                NSString *encodedValue = [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                [queryParts addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
            }
        }
        if (queryParts.count > 0) {
            urlString = [NSString stringWithFormat:@"%@?%@", urlString, [queryParts componentsJoinedByString:@"&"]];
        }
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed for remote request"}];
        completion(nil, error);
        return;
    }

    os_log_info(_log, "Forwarding XRPC request to: %@", urlString);

    // Prepare the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = [self isGetMethod:method] ? @"GET" : @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    // Add JSON body for POST requests
    if (parameters && ![self isGetMethod:method]) {
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&jsonError];
        if (jsonError) {
            NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                             code:FederationErrorNetworkError
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize request parameters",
                                                   NSUnderlyingErrorKey: jsonError}];
            completion(nil, error);
            return;
        }
        request.HTTPBody = jsonData;
    }

    // Execute the request
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

        if (error) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorNetworkError
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Network error during remote request",
                                                              NSUnderlyingErrorKey: error}];
            completion(nil, federationError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorRemoteServerError
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Remote server returned HTTP %ld", (long)httpResponse.statusCode]}];
            completion(nil, federationError);
            return;
        }

        if (!data) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorInvalidResponse
                                                    userInfo:@{NSLocalizedDescriptionKey: @"No data received from remote server"}];
            completion(nil, federationError);
            return;
        }

        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorInvalidResponse
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response from remote server",
                                                              NSUnderlyingErrorKey: jsonError}];
            completion(nil, federationError);
            return;
        }

        completion(jsonResponse, nil);
    }];

    [task resume];
}

- (void)forwardHttpRequest:(NSURL *)url
                    method:(NSString *)method
                   headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                      body:(nullable NSData *)body
                completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion {

    if (!completion) return;

    os_log_info(_log, "Forwarding HTTP request to: %@", url.absoluteString);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;

    // Add headers
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }

    request.HTTPBody = body;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        completion(data, (NSHTTPURLResponse *)response, error);
    }];

    [task resume];
}

- (void)forwardXrpcBinaryRequest:(NSString *)method
                      parameters:(nullable NSDictionary *)parameters
                             did:(NSString *)did
                      completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion {

    if (!completion) return;

    // Resolve the DID to find the PDS endpoint
    NSDictionary *atprotoData = [(DIDResolver *)self.didResolver resolveAtprotoDataForDID:did error:nil];
    if (!atprotoData || !atprotoData[@"pds"]) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorDIDResolutionFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to resolve PDS endpoint for DID"}];
        completion(nil, error);
        return;
    }

    NSString *pdsEndpoint = atprotoData[@"pds"];
    if (![pdsEndpoint hasPrefix:@"http"]) {
        pdsEndpoint = [NSString stringWithFormat:@"https://%@", pdsEndpoint];
    }

    // Construct the XRPC URL
    NSString *xrpcPath = [NSString stringWithFormat:@"/xrpc/%@", method];
    NSString *urlString = [NSString stringWithFormat:@"%@%@", pdsEndpoint, xrpcPath];

    // Add query parameters
    if (parameters) {
        NSMutableArray<NSString *> *queryParts = [NSMutableArray array];
        for (NSString *key in parameters) {
            NSString *value = parameters[key];
            if ([value isKindOfClass:[NSString class]]) {
                NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                NSString *encodedValue = [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                [queryParts addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
            }
        }
        if (queryParts.count > 0) {
            urlString = [NSString stringWithFormat:@"%@?%@", urlString, [queryParts componentsJoinedByString:@"&"]];
        }
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:FederationErrorDomain
                                         code:FederationErrorNetworkError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed for remote request"}];
        completion(nil, error);
        return;
    }

    os_log_info(_log, "Forwarding binary XRPC request to: %@", urlString);

    // Prepare the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Accept"];

    // Execute the request
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {

        if (error) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorNetworkError
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Network error during remote request",
                                                              NSUnderlyingErrorKey: error}];
            completion(nil, federationError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorRemoteServerError
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Remote server returned HTTP %ld", (long)httpResponse.statusCode]}];
            completion(nil, federationError);
            return;
        }

        if (!data) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                        code:FederationErrorInvalidResponse
                                                    userInfo:@{NSLocalizedDescriptionKey: @"No data received from remote server"}];
            completion(nil, federationError);
            return;
        }

        completion(data, nil);
    }];

    [task resume];
}

#pragma mark - Helper Methods

- (BOOL)isGetMethod:(NSString *)method {
    // Methods that typically use GET
    NSArray<NSString *> *getMethods = @[
        @"com.atproto.repo.getRecord",
        @"com.atproto.repo.listRecords",
        @"com.atproto.repo.describeRepo",
        @"com.atproto.sync.getRepo",
        @"com.atproto.sync.getHead",
        @"com.atproto.sync.getBlob",
        @"com.atproto.sync.listBlobs"
    ];

    return [getMethods containsObject:method];
}

@end
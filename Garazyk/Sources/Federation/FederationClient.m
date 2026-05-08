#import "Federation/FederationClient.h"
#import "Core/DID.h"
#import "Debug/PDSLogger.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconSchema.h"
#import "Lexicon/ATProtoLexiconDef.h"
#import "App/PDSConfiguration.h"
#import "Network/PDSSafeHTTPClient.h"
#import "Network/SSRFValidator.h"
#import "Network/HttpRetryPolicy.h"

NSErrorDomain const FederationErrorDomain = @"com.atproto.federation";

static NSString *const kDefaultUserAgent = @"atprotopds/0.1.0";

@interface FederationClient ()
@property (nonatomic, strong) HttpRetryPolicy *retryPolicy;
@end

@implementation FederationClient

static BOOL PDSFederationRunningTests(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    return [env[@"PDS_RUNNING_TESTS"] length] > 0 ||
           [env[@"XCTestConfigurationFilePath"] length] > 0;
}

static NSString *PDSSanitizedURLString(NSURL *url) {
    if (!url) return @"";
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return url.absoluteString ?: @"";
    components.query = nil;
    components.fragment = nil;
    return components.string ?: (url.absoluteString ?: @"");
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _retryPolicy = [[HttpRetryPolicy alloc] init];
        if (PDSFederationRunningTests()) {
            _retryPolicy.initialDelay = 0.01;
        }

        _didResolver = [[DIDResolver alloc] init];
        ((DIDResolver *)_didResolver).plcURL = [PDSConfiguration sharedConfiguration].plcURL;
    }
    return self;
}

- (void)executeRequestWithRetry:(NSURLRequest *)request
                        attempt:(NSInteger)attempt
                     completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion {
    PDSSafeHTTPClientOptions *safeOptions = [[PDSSafeHTTPClientOptions alloc] init];
    safeOptions.timeout = 30.0;
    safeOptions.maxResponseBytes = 10 * 1024 * 1024; // 10 MB
    safeOptions.allowHTTP = NO;
    safeOptions.allowPrivateHosts = NO;
    safeOptions.followRedirects = YES;

    [[PDSSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                   options:safeOptions
                                                completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSInteger statusCode = response ? response.statusCode : 0;
        HttpRetryResult *retryResult = [self.retryPolicy evaluateStatusCode:statusCode
                                                                networkError:error
                                                               attemptNumber:attempt];

        if (retryResult.decision == HttpRetryDecisionRetryAfter) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryResult.retryDelay * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self executeRequestWithRetry:request
                                      attempt:attempt + 1
                                   completion:completion];
            });
            return;
        }

        if (retryResult.decision == HttpRetryDecisionFail) {
            if (error) {
                NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                                code:FederationErrorNetworkError
                                                            userInfo:@{
                                                                NSLocalizedDescriptionKey: @"Network error during remote request",
                                                                NSUnderlyingErrorKey: error
                                                            }];
                completion(nil, nil, federationError);
                return;
            }

            if (statusCode < 200 || statusCode >= 300) {
                NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                                code:FederationErrorRemoteServerError
                                                            userInfo:@{
                                                                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Remote server returned HTTP %ld", (long)statusCode]
                                                            }];
                completion(nil, response, federationError);
                return;
            }
        }

        if (!data) {
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                            code:FederationErrorInvalidResponse
                                                        userInfo:@{
                                                            NSLocalizedDescriptionKey: @"No data received from remote server"
                                                        }];
            completion(nil, response, federationError);
            return;
        }

        completion(data, response, nil);
    }];
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

    // SSRF protection is handled by PDSSafeHTTPClient during the actual request,
    // eliminating the validate-before-fetch TOCTOU gap.

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

    PDS_LOG_SERVICE_INFO(@"Forwarding XRPC request (method=%@, did=%@) to %@", method ?: @"", did ?: @"", PDSSanitizedURLString(url));

    // Prepare the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = [self isGetMethod:method] ? @"GET" : @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];

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

    [self executeRequestWithRetry:request attempt:0 completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }

        NSError *jsonError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![parsed isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *userInfo = [@{
                NSLocalizedDescriptionKey: @"Invalid JSON response from remote server"
            } mutableCopy];
            if (jsonError) {
                userInfo[NSUnderlyingErrorKey] = jsonError;
            }
            NSError *federationError = [NSError errorWithDomain:FederationErrorDomain
                                                            code:FederationErrorInvalidResponse
                                                        userInfo:userInfo];
            completion(nil, federationError);
            return;
        }

        completion((NSDictionary *)parsed, nil);
    }];
}

- (void)forwardHttpRequest:(NSURL *)url
                    method:(NSString *)method
                   headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                      body:(nullable NSData *)body
                completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion {

    if (!completion) return;

    PDS_LOG_SERVICE_INFO(@"Forwarding HTTP request (method=%@) to %@", method ?: @"", PDSSanitizedURLString(url));

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;

    // Add headers
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }

    request.HTTPBody = body;

    PDSSafeHTTPClientOptions *safeOptions = [[PDSSafeHTTPClientOptions alloc] init];
    safeOptions.timeout = 30.0;
    safeOptions.maxResponseBytes = 10 * 1024 * 1024; // 10 MB
    safeOptions.allowHTTP = NO;
    safeOptions.allowPrivateHosts = NO;
    safeOptions.followRedirects = YES;

    [[PDSSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                   options:safeOptions
                                                completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        completion(data, response, error);
    }];
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

    // SSRF protection is handled by PDSSafeHTTPClient during the actual request,
    // eliminating the validate-before-fetch TOCTOU gap.

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

    PDS_LOG_SERVICE_INFO(@"Forwarding binary XRPC request (method=%@, did=%@) to %@", method ?: @"", did ?: @"", PDSSanitizedURLString(url));

    // Prepare the request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Accept"];
    [request setValue:kDefaultUserAgent forHTTPHeaderField:@"User-Agent"];

    [self executeRequestWithRetry:request attempt:0 completion:^(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }
        completion(data, nil);
    }];
}

#pragma mark - Helper Methods

- (BOOL)isGetMethod:(NSString *)method {
    // Check the lexicon registry first
    ATProtoLexiconSchema *schema = [[ATProtoLexiconRegistry sharedRegistry] schemaForNSID:method];
    if (schema) {
        ATProtoLexiconDef *mainDef = [schema mainDefinition];
        if (mainDef) {
            return mainDef.type == ATProtoLexiconDefTypeQuery;
        }
    }

    // Fallback for unregistered lexicons
    static NSSet<NSString *> *getFallbacks = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        getFallbacks = [NSSet setWithArray:@[
            @"com.atproto.repo.getRecord",
            @"com.atproto.repo.listRecords",
            @"com.atproto.repo.describeRepo",
            @"com.atproto.sync.getRepo",
            @"com.atproto.sync.getHead",
            @"com.atproto.sync.getBlob",
            @"com.atproto.sync.listBlobs"
        ]];
    });

    return [getFallbacks containsObject:method];
}

@end

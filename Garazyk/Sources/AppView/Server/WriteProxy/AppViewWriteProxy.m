/*!
 @file AppViewWriteProxy.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/WriteProxy/AppViewWriteProxy.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/PDSSafeHTTPClient.h"
#import "Debug/PDSLogger.h"

NSErrorDomain const AppViewWriteProxyErrorDomain = @"AppViewWriteProxy";

@interface AppViewWriteProxy ()

@property (nonatomic, strong) AppViewDatabase *database;

@end

@implementation AppViewWriteProxy

- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (void)proxyWriteRequest:(HttpRequest *)request
                  response:(HttpResponse *)response
                     nsid:(NSString *)nsid
                 callerDID:(NSString *)callerDID {
    // 1. Parse the input body
    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Request body required for write proxy"
        }];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *input = [NSJSONSerialization JSONObjectWithData:bodyData
                                                         options:0
                                                           error:&jsonError];
    if (![input isKindOfClass:[NSDictionary class]]) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Invalid JSON body"
        }];
        return;
    }

    // 2. Determine write type (create vs update)
    BOOL isUpdate = input[@"uri"] != nil &&
                    [input[@"uri"] isKindOfClass:[NSString class]] &&
                    [input[@"uri"] length] > 0;

    // 3. Resolve the caller's PDS endpoint
    NSString *pdsEndpoint = [self resolvePDSEndpointForDID:callerDID];
    if (!pdsEndpoint) {
        response.statusCode = 502;
        [response setJsonBody:@{
            @"error": @"UpstreamError",
            @"message": [NSString stringWithFormat:
                @"Could not resolve PDS endpoint for DID %@", callerDID]
        }];
        return;
    }

    // 4. Construct the PDS XRPC request
    NSString *pdsNSID = isUpdate
        ? @"com.atproto.repo.updateRecord"
        : @"com.atproto.repo.createRecord";

    NSString *pdsURL = [NSString stringWithFormat:@"%@/xrpc/%@",
                        pdsEndpoint, pdsNSID];

    // 5. Forward the request with the caller's auth credentials
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader || authHeader.length == 0) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"AuthenticationRequired",
            @"message": @"Authentication required for write operations"
        }];
        return;
    }

    // Build the proxied request body
    NSMutableDictionary *proxyBody = [NSMutableDictionary dictionary];
    if (isUpdate) {
        // Update: forward the existing record with new value
        proxyBody[@"repo"] = callerDID;
        proxyBody[@"uri"] = input[@"uri"];
        proxyBody[@"value"] = input[@"value"] ?: input;
    } else {
        // Create: construct the createRecord payload
        proxyBody[@"repo"] = callerDID;
        proxyBody[@"collection"] = input[@"collection"] ?: nsid;
        proxyBody[@"record"] = input[@"record"] ?: input;
        if (input[@"rkey"]) {
            proxyBody[@"rkey"] = input[@"rkey"];
        }
        if (input[@"swapCommit"]) {
            proxyBody[@"swapCommit"] = input[@"swapCommit"];
        }
    }

    NSData *proxyBodyData = [NSJSONSerialization dataWithJSONObject:proxyBody
                                                             options:0
                                                               error:nil];

    // 6. Execute the proxied request via PDSSafeHTTPClient (SSRF protection)
    NSURL *url = [NSURL URLWithString:pdsURL];
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    urlRequest.HTTPMethod = @"POST";
    [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [urlRequest setValue:authHeader forHTTPHeaderField:@"Authorization"];
    urlRequest.HTTPBody = proxyBodyData;

    // Forward DPoP proof if present
    NSString *dpopHeader = [request headerForKey:@"DPoP"];
    if (dpopHeader.length > 0) {
        [urlRequest setValue:dpopHeader forHTTPHeaderField:@"DPoP"];
    }

    PDSSafeHTTPClientOptions *safeOptions = [[PDSSafeHTTPClientOptions alloc] init];
    safeOptions.timeout = 30.0;
    safeOptions.maxResponseBytes = 256 * 1024; // 256 KB
    safeOptions.allowHTTP = NO;
    safeOptions.allowPrivateHosts = NO;
    safeOptions.followRedirects = NO;

    NSHTTPURLResponse *urlResponse = nil;
    NSError *requestError = nil;
    NSData *responseData = [[PDSSafeHTTPClient sharedClient]
        sendSynchronousRequest:urlRequest
                       options:safeOptions
                      response:&urlResponse
                         error:&requestError];

    // 7. Return the PDS response
    if (requestError) {
        PDS_LOG_WARN(@"[WriteProxy] PDS request failed for %@: %@",
                     nsid, requestError.localizedDescription);

        // Map SSRF errors to 502, other errors to their natural code
        NSInteger errorCode = 502;
        if ([requestError.domain isEqualToString:PDSSafeHTTPClientErrorDomain]) {
            switch (requestError.code) {
                case PDSSafeHTTPClientErrorInvalidURL:
                case PDSSafeHTTPClientErrorUnsupportedScheme:
                    errorCode = 400;
                    break;
                case PDSSafeHTTPClientErrorSSRFBlocked:
                    errorCode = 403;
                    break;
                default:
                    break;
            }
        }

        response.statusCode = errorCode;
        [response setJsonBody:@{
            @"error": @"UpstreamError",
            @"message": requestError.localizedDescription
        }];
        return;
    }

    response.statusCode = urlResponse.statusCode;

    // Try to parse the response as JSON
    if (responseData && responseData.length > 0) {
        NSDictionary *responseJSON = [NSJSONSerialization JSONObjectWithData:responseData
                                                                    options:0
                                                                      error:nil];
        if ([responseJSON isKindOfClass:[NSDictionary class]]) {
            [response setJsonBody:responseJSON];
        } else {
            [response setBodyData:responseData];
        }
    }
}

- (BOOL)isWriteProcedure:(NSDictionary *)input nsid:(NSString *)nsid {
    if (!input) return NO;

    // If the input has a $type field, it's a record write
    NSString *recordType = input[@"$type"];
    if ([recordType isKindOfClass:[NSString class]] && recordType.length > 0) {
        return YES;
    }

    // If the input has a "record" key, it's a createRecord-style write
    if (input[@"record"] != nil) {
        return YES;
    }

    // If the input has a "uri" key, it's an updateRecord-style write
    if (input[@"uri"] != nil && [input[@"uri"] isKindOfClass:[NSString class]]) {
        return YES;
    }

    // Known write NSIDs
    NSSet *writeNSIDs = [NSSet setWithArray:@[
        @"com.atproto.repo.createRecord",
        @"com.atproto.repo.updateRecord",
        @"com.atproto.repo.deleteRecord",
        @"com.atproto.repo.applyWrites",
    ]];
    if ([writeNSIDs containsObject:nsid]) {
        return YES;
    }

    return NO;
}

#pragma mark - Private

- (nullable NSString *)resolvePDSEndpointForDID:(NSString *)did {
    // Try to resolve from the database first (handles table)
    NSError *error = nil;
    NSString *handle = [self.database resolveDIDToHandle:did error:&error];
    if (handle) {
        // Construct PDS URL from handle
        // For now, assume HTTPS + handle
        return [NSString stringWithFormat:@"https://%@", handle];
    }

    // TODO: Resolve via DID document (PLC directory or did:web)
    // This requires the DID resolver infrastructure
    PDS_LOG_WARN(@"[WriteProxy] Could not resolve PDS endpoint for DID %@", did);
    return nil;
}

@end

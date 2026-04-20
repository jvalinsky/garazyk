#import "RelayXrpcRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "PLC/DIDPLCResolver.h"
#import "Network/XrpcLexiconResolver.h"
#import "Core/DID.h"
#import "Debug/PDSLogger.h"

// DID validation helper
static BOOL isValidDID(NSString *did) {
    if (!did || did.length < 7) return NO;
    return [did hasPrefix:@"did:plc:"] || [did hasPrefix:@"did:web:"];
}

@implementation RelayXrpcRoutePack
{
    RelayRepoStateManager *_repoStateManager;
    SubscribeReposHandler *_subscribeReposHandler;
}

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
{
    return [self initWithRepoStateManager:repoStateManager
                     subscribeReposHandler:subscribeReposHandler
                                 plcResolver:nil];
}

- (instancetype)initWithRepoStateManager:(RelayRepoStateManager *)repoStateManager
                  subscribeReposHandler:(nullable SubscribeReposHandler *)subscribeReposHandler
                              plcResolver:(nullable DIDPLCResolver *)plcResolver
{
    self = [super init];
    if (self)
    {
        _repoStateManager = repoStateManager;
        _subscribeReposHandler = subscribeReposHandler;
        _plcResolver = plcResolver;
    }
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server
{
    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.listRepos"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleListRepos:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.getHead"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetHead:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.getLatestCommit"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetLatestCommit:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.getRepoStatus"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetRepoStatus:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.getHostStatus"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetHostStatus:request response:response];
             }];

    [server addRoute:@"POST"
                path:@"/xrpc/com.atproto.sync.requestCrawl"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleRequestCrawl:request response:response];
             }];

    [server addRoute:@"GET"
                path:@"/xrpc/com.atproto.sync.getRepo"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleGetRepo:request response:response];
             }];

    if (_subscribeReposHandler)
    {
        [server addRoute:@"OPTIONS"
                    path:@"/xrpc/com.atproto.sync.subscribeRepos"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
                     [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
                     response.statusCode = HttpStatusOK;
                 }];

        [server addWebSocketRoute:@"/xrpc/com.atproto.sync.subscribeRepos"
                          handler:^(HttpRequest *request, HttpResponse *response,
                                    id<PDSNetworkConnection> connection) {
                              [_subscribeReposHandler acceptUpgradedConnection:connection
                                                                         request:request];
                          }];
    }
}

#pragma mark - listRepos

- (void)handleListRepos:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *limitParam = [request queryParamForKey:@"limit"];
    NSInteger limit = 100;
    if (limitParam.length > 0)
    {
        if (![[NSScanner scannerWithString:limitParam] scanInteger:&limit] || limit < 1 || limit > 1000)
        {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"limit must be an integer between 1 and 1000"
            }];
            return;
        }
    }

    NSString *cursorParam = [request queryParamForKey:@"cursor"];
    NSInteger startIndex = 0;
    if (cursorParam.length > 0)
    {
        if (![[NSScanner scannerWithString:cursorParam] scanInteger:&startIndex] || startIndex < 0)
        {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{
                @"error": @"InvalidRequest",
                @"message": @"cursor must be a non-negative integer"
            }];
            return;
        }
    }

    NSArray *allRepos = [_repoStateManager allRepos];
    NSInteger totalRepos = allRepos.count;

    NSMutableArray *repos = [NSMutableArray array];
    NSInteger scanIndex = MIN(startIndex, totalRepos);
    while (scanIndex < totalRepos && repos.count < limit)
    {
        NSString *repoDid = allRepos[(NSUInteger)scanIndex];
        NSString *rootCid = [_repoStateManager rootCIDForRepo:repoDid];
        NSString *rev = [_repoStateManager revForRepo:repoDid];
        RelayRepoStatus status = [_repoStateManager statusForRepo:repoDid];

        if (rootCid.length > 0)
        {
            [repos addObject:@{
                @"did": repoDid,
                @"head": rootCid,
                @"rev": rev ?: @"",
                @"active": @(status == RelayRepoStatusActive)
            }];
        }
        scanIndex += 1;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:repos forKey:@"repos"];
    if (scanIndex < totalRepos)
    {
        result[@"cursor"] = [NSString stringWithFormat:@"%ld", (long)scanIndex];
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
}

#pragma mark - getHead (deprecated)

- (void)handleGetHead:(HttpRequest *)request response:(HttpResponse *)response
{
    // DEPRECATED endpoint - use getLatestCommit instead
    // Output format: { "root": "<cid>" }
    NSString *didParam = [request queryParamForKey:@"did"];
    if (didParam.length == 0)
    {
        didParam = [request queryParamForKey:@"repo"]; // legacy parameter
    }
    if (didParam.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"did parameter is required"
        }];
        return;
    }

    NSString *rootCid = [_repoStateManager rootCIDForRepo:didParam];
    if (!rootCid)
    {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"HeadNotFound",
            @"message": [NSString stringWithFormat:@"Head not found for repo: %@", didParam]
        }];
        return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{ @"root": rootCid }];
}

#pragma mark - getLatestCommit

- (void)handleGetLatestCommit:(HttpRequest *)request response:(HttpResponse *)response
{
    // Current endpoint - returns cid and rev
    // Lexicon: com.atproto.sync.getLatestCommit
    // Output: { "cid": "<cid>", "rev": "<rev>" }
    NSString *didParam = [request queryParamForKey:@"did"];
    if (didParam.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"did parameter is required"
        }];
        return;
    }

    NSString *rootCid = [_repoStateManager rootCIDForRepo:didParam];
    if (!rootCid)
    {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"RepoNotFound",
            @"message": [NSString stringWithFormat:@"Repo not found: %@", didParam]
        }];
        return;
    }

    NSString *rev = [_repoStateManager revForRepo:didParam];
    if (!rev)
    {
        rev = @"";
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{
        @"cid": rootCid,
        @"rev": rev
    }];
}

#pragma mark - getRepoStatus

- (void)handleGetRepoStatus:(HttpRequest *)request response:(HttpResponse *)response
{
    // Lexicon: com.atproto.sync.getRepoStatus
    // Output: { "did": "...", "active": bool, "status": "...", "rev": "..." }
    NSString *didParam = [request queryParamForKey:@"did"];
    if (didParam.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"did parameter is required"
        }];
        return;
    }

    // Check if repo is known to the relay
    NSString *rootCid = [_repoStateManager rootCIDForRepo:didParam];
    RelayRepoStatus status = [_repoStateManager statusForRepo:didParam];

    // If repo has no root CID and status is default, it's unknown
    if (!rootCid && status == RelayRepoStatusActive)
    {
        // Check if we've ever seen this repo
        NSString *rev = [_repoStateManager revForRepo:didParam];
        if (!rev)
        {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{
                @"error": @"RepoNotFound",
                @"message": [NSString stringWithFormat:@"Repo not found: %@", didParam]
            }];
            return;
        }
    }

    // Build response
    BOOL active = (status == RelayRepoStatusActive);
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        didParam, @"did",
        @(active), @"active",
        nil];

    // Map status enum to string
    if (!active)
    {
        NSString *statusStr = nil;
        switch (status)
        {
            case RelayRepoStatusDesynchronized:
                statusStr = @"desynchronized";
                break;
            case RelayRepoStatusInProgress:
                statusStr = @"in-progress";
                break;
            case RelayRepoStatusThrottled:
                statusStr = @"throttled";
                break;
            case RelayRepoStatusTombstoned:
                statusStr = @"deleted";
                break;
            default:
                break;
        }
        if (statusStr)
        {
            body[@"status"] = statusStr;
        }
    }

    // Include rev if active
    if (active)
    {
        NSString *rev = [_repoStateManager revForRepo:didParam];
        if (rev && rev.length > 0)
        {
            body[@"rev"] = rev;
        }
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:body];
}

#pragma mark - getHostStatus

- (void)handleGetHostStatus:(HttpRequest *)request response:(HttpResponse *)response
{
    // Lexicon: com.atproto.sync.getHostStatus
    // Output: { "hostname": "...", "seq": 123, "status": "...", "accountCount": 456 }
    NSString *hostnameParam = [request queryParamForKey:@"hostname"];
    if (hostnameParam.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"hostname parameter is required"
        }];
        return;
    }

    // Normalize hostname (remove scheme if present)
    NSString *normalizedHostname = hostnameParam;
    if ([normalizedHostname hasPrefix:@"https://"])
    {
        normalizedHostname = [normalizedHostname substringFromIndex:8];
    }
    else if ([normalizedHostname hasPrefix:@"http://"])
    {
        normalizedHostname = [normalizedHostname substringFromIndex:7];
    }

    // Remove trailing slash and path
    NSRange pathRange = [normalizedHostname rangeOfString:@"/"];
    if (pathRange.location != NSNotFound)
    {
        normalizedHostname = [normalizedHostname substringToIndex:pathRange.location];
    }

    // Remove port for lookup
    NSString *lookupHostname = normalizedHostname;
    NSRange portRange = [lookupHostname rangeOfString:@":"];
    if (portRange.location != NSNotFound)
    {
        lookupHostname = [lookupHostname substringToIndex:portRange.location];
    }

    // Check if we have this upstream
    if (!_upstreamManager)
    {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"HostNotFound",
            @"message": [NSString stringWithFormat:@"Host not found: %@", hostnameParam]
        }];
        return;
    }

    // Find matching upstream by hostname
    NSArray<NSString *> *allUpstreams = [_upstreamManager allUpstreams];
    NSString *matchedUpstream = nil;
    for (NSString *upstream in allUpstreams)
    {
        // Extract hostname from URL
        NSURL *upstreamURL = [NSURL URLWithString:upstream];
        if (!upstreamURL)
        {
            // Try adding scheme
            upstreamURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", upstream]];
        }
        NSString *upstreamHost = upstreamURL.host ?: upstream;
        if ([upstreamHost.lowercaseString isEqualToString:lookupHostname.lowercaseString])
        {
            matchedUpstream = upstream;
            break;
        }
    }

    if (!matchedUpstream)
    {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"HostNotFound",
            @"message": [NSString stringWithFormat:@"Host not found: %@", hostnameParam]
        }];
        return;
    }

    // Build response
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        normalizedHostname, @"hostname",
        nil];

    int64_t seq = [_upstreamManager seqForUpstream:matchedUpstream];
    if (seq > 0)
    {
        body[@"seq"] = @(seq);
    }

    NSUInteger accountCount = [_upstreamManager accountCountForUpstream:matchedUpstream];
    if (accountCount > 0)
    {
        body[@"accountCount"] = @(accountCount);
    }

    RelayHostStatus status = [_upstreamManager statusForUpstream:matchedUpstream];
    NSString *statusStr = @"disconnected";
    switch (status)
    {
        case RelayHostStatusActive:
            statusStr = @"active";
            break;
        case RelayHostStatusError:
            statusStr = @"error";
            break;
        case RelayHostStatusDisconnected:
            statusStr = @"disconnected";
            break;
    }
    body[@"status"] = statusStr;

    response.statusCode = HttpStatusOK;
    [response setJsonBody:body];
}

#pragma mark - requestCrawl

- (void)handleRequestCrawl:(HttpRequest *)request response:(HttpResponse *)response
{
    // Lexicon: com.atproto.sync.requestCrawl
    // Input: { "hostname": "..." }
    // Procedure: Request the relay to crawl a new PDS

    // Parse JSON body
    NSData *bodyData = request.body;
    if (!bodyData || bodyData.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Request body required"
        }];
        return;
    }

    NSError *parseError = nil;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&parseError];
    if (!body || ![body isKindOfClass:[NSDictionary class]])
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Invalid JSON body"
        }];
        return;
    }

    NSString *hostname = body[@"hostname"];
    if (!hostname || hostname.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"hostname field required"
        }];
        return;
    }

    // Parse hostname - normalize and detect scheme
    NSString *normalizedHostname = hostname;
    BOOL useSSL = YES;

    // Remove scheme if present
    if ([normalizedHostname hasPrefix:@"https://"])
    {
        normalizedHostname = [normalizedHostname substringFromIndex:8];
    }
    else if ([normalizedHostname hasPrefix:@"http://"])
    {
        normalizedHostname = [normalizedHostname substringFromIndex:7];
        useSSL = NO;
    }

    // Remove path
    NSRange pathRange = [normalizedHostname rangeOfString:@"/"];
    if (pathRange.location != NSNotFound)
    {
        normalizedHostname = [normalizedHostname substringToIndex:pathRange.location];
    }

    // Validate hostname format
    if (normalizedHostname.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"hostname field empty or invalid"
        }];
        return;
    }

    // Check if we have an upstream manager
    if (!_upstreamManager)
    {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{
            @"error": @"InternalError",
            @"message": @"Relay upstream manager not configured"
        }];
        return;
    }

    // Build the upstream URL
    NSString *upstreamURL = useSSL ?
        [NSString stringWithFormat:@"https://%@", normalizedHostname] :
        [NSString stringWithFormat:@"http://%@", normalizedHostname];

    // Check if host is reachable (async validateHost callback)
    // For now, we'll do a synchronous check
    // TODO: In production, this should be async to avoid blocking
    [_upstreamManager validateHost:upstreamURL completion:^(BOOL reachable, NSError * _Nullable error) {
        // This callback happens after we return, so we can't use it here
        // For initial implementation, just add the upstream and let the manager handle connection
    }];

    // Add upstream for crawling
    [_upstreamManager addUpstream:upstreamURL];

    PDS_LOG_SYNC_INFO(@"Relay requestCrawl: Added upstream %@", upstreamURL);

    // Success - return empty response (per lexicon)
    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
}

#pragma mark - getRepo

- (void)handleGetRepo:(HttpRequest *)request response:(HttpResponse *)response
{
    // Per ATProto spec and indigo reference: relay getRepo returns HTTP 302 redirect
    // to the source PDS's getRepo endpoint, not the CAR data itself.
    // Reference: indigo/cmd/relay/stubs.go:125-158

    NSString *didParam = [request queryParamForKey:@"did"];
    if (didParam.length == 0)
    {
        // Also check legacy 'repo' parameter for compatibility
        didParam = [request queryParamForKey:@"repo"];
    }
    if (didParam.length == 0)
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"did parameter is required"
        }];
        return;
    }

    // Validate DID format
    if (!isValidDID(didParam))
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": [NSString stringWithFormat:@"Invalid DID format: %@ (must be did:plc or did:web)", didParam]
        }];
        return;
    }

    // Resolve the DID document to get the PDS endpoint
    NSError *resolveError = nil;
    NSDictionary *didDoc = nil;

    if ([didParam hasPrefix:@"did:plc:"] && self.plcResolver)
    {
        didDoc = [self.plcResolver resolveDID:didParam error:&resolveError];
    }
    else if ([didParam hasPrefix:@"did:web:"])
    {
        // For did:web, fetch the DID document from the web endpoint
        NSString *domain = [didParam substringFromIndex:8]; // Remove "did:web:"
        NSString *urlString = [NSString stringWithFormat:@"https://%@/.well-known/did.json", domain];
        NSURL *url = [NSURL URLWithString:urlString];
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&resolveError];
        if (data)
        {
            didDoc = [NSJSONSerialization JSONObjectWithData:data options:0 error:&resolveError];
        }
    }
    else
    {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{
            @"error": @"InvalidRequest",
            @"message": @"Unsupported DID method (must be did:plc or did:web)"
        }];
        return;
    }

    if (!didDoc || resolveError)
    {
        PDS_LOG_WARN(@"Relay getRepo: Failed to resolve DID %@: %@", didParam,
                     resolveError.localizedDescription ?: @"unknown error");
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"RepoNotFound",
            @"message": [NSString stringWithFormat:@"Could not resolve DID: %@", didParam]
        }];
        return;
    }

    // Wrap as DIDDocument for endpoint extraction
    DIDDocument *didDocument = [DIDDocument documentWithJSON:didDoc error:&resolveError];
    if (!didDocument)
    {
        PDS_LOG_WARN(@"Relay getRepo: Invalid DID document for %@: %@", didParam,
                     resolveError.localizedDescription ?: @"unknown error");
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"RepoNotFound",
            @"message": [NSString stringWithFormat:@"Invalid DID document: %@", didParam]
        }];
        return;
    }

    // Extract PDS endpoint from DID document
    NSError *endpointError = nil;
    NSString *pdsEndpoint = [XrpcLexiconResolver pdsEndpointFromDidDocument:didDocument error:&endpointError];

    if (!pdsEndpoint || pdsEndpoint.length == 0)
    {
        PDS_LOG_WARN(@"Relay getRepo: No PDS endpoint in DID document for %@", didParam);
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
            @"error": @"RepoNotFound",
            @"message": @"DID document has no AtprotoPersonalDataServer endpoint"
        }];
        return;
    }

    // Normalize PDS endpoint (remove trailing slash)
    if ([pdsEndpoint hasSuffix:@"/"])
    {
        pdsEndpoint = [pdsEndpoint substringWithRange:NSMakeRange(0, pdsEndpoint.length - 1)];
    }

    // Build redirect URL to PDS's getRepo endpoint
    NSURLComponents *redirectComponents = [NSURLComponents componentsWithString:pdsEndpoint];
    if (!redirectComponents)
    {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{
            @"error": @"InternalError",
            @"message": @"Invalid PDS endpoint URL in DID document"
        }];
        return;
    }

    // Append the XRPC path
    NSString *basePath = redirectComponents.path ?: @"";
    if (basePath.length == 0 || [basePath isEqualToString:@"/"])
    {
        redirectComponents.path = @"/xrpc/com.atproto.sync.getRepo";
    }
    else
    {
        redirectComponents.path = [basePath stringByAppendingString:@"/xrpc/com.atproto.sync.getRepo"];
    }

    // Add query parameters
    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray array];
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"did" value:didParam]];

    // Preserve the 'since' parameter if provided
    NSString *sinceParam = [request queryParamForKey:@"since"];
    if (sinceParam.length > 0)
    {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"since" value:sinceParam]];
    }

    redirectComponents.queryItems = queryItems;

    NSURL *redirectURL = redirectComponents.URL;
    if (!redirectURL)
    {
        response.statusCode = HttpStatusInternalServerError;
        [response setJsonBody:@{
            @"error": @"InternalError",
            @"message": @"Failed to construct redirect URL"
        }];
        return;
    }

    PDS_LOG_INFO(@"Relay getRepo: Redirecting %@ to %@", didParam, redirectURL.absoluteString);

    // HTTP 302 Found (temporary redirect) per indigo reference
    response.statusCode = 302;
    [response setHeader:redirectURL.absoluteString forKey:@"Location"];
}

@end

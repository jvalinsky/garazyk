// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczStreamplacePeerDemo.h"
#import "Video/GZJelczStreamplaceBlobFetcher.h"
#import "Video/GZJelczStreamplaceCompatServe.h"
#import "Video/GZJelczStreamplaceOriginHints.h"
#import "Video/GZJelczPeerProviderIndex.h"
#import "Video/GZJelczOriginAnnouncer.h"
#import "Video/GZJelczIrohSidecarBlobFetcher.h"
#import "Video/GZJelczIrohSidecarPeerRegistry.h"
#import "Video/GZJelczIrohSidecarURL.h"
#import "Video/GZJelczStreamplaceIrohBridge.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Security/PDSSecurityCompare.h"
#import "Debug/GZLogger.h"

static NSString * const kDemoHTMLResourceRelative =
    @"Garazyk/Resources/jelcz-demo/streamplace-peer.html";
static NSString * const kOverwatchHTMLResourceRelative =
    @"Garazyk/Resources/jelcz-demo/streamplace-overwatch.html";

@interface GZJelczDemoURLSessionHTTPClient : NSObject <ATProtoCAMirrorHTTPClient>
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation GZJelczDemoURLSessionHTTPClient
- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30.0;
        cfg.HTTPMaximumConnectionsPerHost = 4;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    (void)options;
    __block NSData *body = nil;
    __block NSHTTPURLResponse *resp = nil;
    __block NSError *reqError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[self.session dataTaskWithRequest:request
                     completionHandler:^(NSData *data, NSURLResponse *urlResp, NSError *taskError) {
                         body = data;
                         resp = (NSHTTPURLResponse *)urlResp;
                         reqError = taskError;
                         dispatch_semaphore_signal(sema);
                     }] resume];
    NSTimeInterval timeout = request.timeoutInterval > 0 ? request.timeoutInterval : 30.0;
    NSTimeInterval wait = timeout + 2.0;
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC))) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"HTTP client timed out"}];
        }
        return nil;
    }
    if (response) *response = resp;
    if (error && reqError) *error = reqError;
    return reqError ? nil : body;
}
@end

static const NSUInteger kDemoRecentServeLimit = 24;
static const NSUInteger kDemoDefaultSeedPayloadMaxBytes = 8ULL * 1024ULL * 1024ULL;
static const NSUInteger kDemoDefaultMutationJSONMaxBytes = 64ULL * 1024ULL;

/** The normalized provider boundary admits only HTTP(S); preserve its actual transport. */
static NSString *GZJelczDemoPeerSourceForHTTPBase(NSString *base) {
    NSString *scheme = [NSURL URLWithString:base].scheme.lowercaseString;
    return [scheme isEqualToString:@"https"] ? @"https-peer" : @"http-peer";
}

/**
 The seed route normally fan-outs to the configured lab mesh.  A caller may
 suppress that behavior with `?fanout=0` when it needs to prove a specific
 transport transfer into an initially-empty destination.
 */
static BOOL GZJelczDemoSeedFanoutEnabled(ATProtoHttpRequest *request) {
    NSString *value = [[request queryParamForKey:@"fanout"] lowercaseString];
    return !([value isEqualToString:@"0"] || [value isEqualToString:@"false"] ||
             [value isEqualToString:@"no"] || [value isEqualToString:@"off"]);
}

@interface GZJelczStreamplacePeerDemo ()
@property (atomic, assign, readwrite) NSUInteger peeredObjectCount;
@property (atomic, assign, readwrite) NSUInteger proxiedByteCount;
@property (atomic, assign, readwrite) NSUInteger localServeCount;
@property (atomic, assign, readwrite) NSUInteger proxyServeCount;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *peerSessions;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recentServes;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) id<ATProtoCAMirrorHTTPClient> sessionHTTPClient;
@property (nonatomic, strong) NSDictionary *cachedOverwatchSnapshot;
@property (nonatomic, assign) NSTimeInterval cachedOverwatchAt;
@property (nonatomic, assign) NSTimeInterval lastIrohRefreshAt;
@property (nonatomic, assign) BOOL overwatchRefreshInFlight;
@end

@implementation GZJelczStreamplacePeerDemo

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                         httpClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                    upstreamBaseURL:(NSString *)upstreamBaseURL
                      publicBaseURL:(NSString *)publicBaseURL {
    NSParameterAssert(objectStore);
    (void)httpClient; // retained for API compatibility; demo uses NSURLSession client
    NSParameterAssert(upstreamBaseURL.length > 0);
    NSParameterAssert(publicBaseURL.length > 0);
    self = [super init];
    if (self) {
        _objectStore = objectStore;
        _sessionHTTPClient = [[GZJelczDemoURLSessionHTTPClient alloc] init];
        _httpClient = _sessionHTTPClient;
        _upstreamBaseURL = [[GZJelczStreamplaceOriginHints normalizedProviderBaseURL:upstreamBaseURL]
                            copy] ?: [upstreamBaseURL copy];
        _publicBaseURL = [[publicBaseURL stringByTrimmingCharactersInSet:
                           [NSCharacterSet characterSetWithCharactersInString:@"/"]] copy];
        _fullPeerMaxBytes = 8ULL * 1024ULL * 1024ULL;
        _seedPayloadMaxBytes = kDemoDefaultSeedPayloadMaxBytes;
        _mutationJSONMaxBytes = kDemoDefaultMutationJSONMaxBytes;
        _peerSessions = [NSMutableDictionary dictionary];
        _recentServes = [NSMutableArray array];
        _lock = [[NSLock alloc] init];
        _peerHTTPSProviders = @[];
        _originEntries = @[];
        _allowedStreamers = [NSSet set];
        _allowedBroadcasters = [NSSet set];
        _nodeName = @"jelcz";
        _meshNodes = @[];
        _irohSidecarTrustLan = NO;
        _irohPeerSidecarURLs = @[];
        NSString *upHost = [NSURL URLWithString:_upstreamBaseURL].host.lowercaseString;
        if ([upHost isEqualToString:@"stream.place"] || [upHost hasSuffix:@".stream.place"]) {
            _vodOriginBaseURL = [_upstreamBaseURL copy];
        } else {
            _vodOriginBaseURL = @"https://stream.place";
        }
    }
    return self;
}

- (void)refreshIrohPeerRegistryIfConfigured {
    if (self.irohSidecarURL.length == 0) {
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (self.irohPeerRegistry && (now - self.lastIrohRefreshAt) < 8.0) {
        return;
    }
    self.lastIrohRefreshAt = now;
    self.irohPeerRegistry =
        [GZJelczIrohSidecarPeerRegistry registryWithHTTPClient:self.httpClient
                                               localSidecarURL:self.irohSidecarURL
                                               peerSidecarURLs:self.irohPeerSidecarURLs
                                                      nodeName:self.nodeName
                                                      trustLan:self.irohSidecarTrustLan
                                               capabilityToken:self.irohSidecarCapabilityToken];
}

- (NSArray<NSString *> *)effectiveIrohProviderHints {
    NSMutableOrderedSet<NSString *> *hints = [NSMutableOrderedSet orderedSet];
    if (self.irohPeerRegistry) {
        [hints addObjectsFromArray:[self.irohPeerRegistry irohProviderHints]];
    }
    if (self.irohBootstrapEndpointId.length > 0) {
        [hints addObject:[NSString stringWithFormat:@"iroh://%@", self.irohBootstrapEndpointId]];
    }
    return hints.array;
}

- (NSDictionary *)offerBytesToIrohSidecar:(NSData *)bytes error:(NSError **)error {
    NSString *base = [GZJelczIrohSidecarURL normalizedHTTPBase:self.irohSidecarURL
                                                      trustLan:self.irohSidecarTrustLan];
    if (base.length == 0 || bytes.length == 0) {
        return nil;
    }
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/v1/offer"]];
    if (!url) {
        return nil;
    }
    NSString *b64 = [bytes base64EncodedStringWithOptions:0];
    NSDictionary *payload = @{ @"payload_base64": b64 };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!body) {
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 60.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (self.irohSidecarCapabilityToken.length > 0) {
        [req setValue:[@"Bearer " stringByAppendingString:self.irohSidecarCapabilityToken]
forHTTPHeaderField:@"Authorization"];
    }
    req.HTTPBody = body;
    NSHTTPURLResponse *resp = nil;
    NSData *respBody = [self.httpClient sendSynchronousRequest:req
                                                       options:nil
                                                      response:&resp
                                                         error:error];
    if (!respBody || resp.statusCode != 200) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:respBody options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (nullable NSDictionary *)postJSON:(NSDictionary *)payload
                             toBase:(NSString *)base
                               path:(NSString *)path {
    if (base.length == 0 || path.length == 0) {
        return nil;
    }
    NSString *trimmed = [base stringByTrimmingCharactersInSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", trimmed, path]];
    if (!url) {
        return nil;
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!body) {
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 45.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (self.apiToken.length > 0) {
        [req setValue:[@"Bearer " stringByAppendingString:self.apiToken]
               forHTTPHeaderField:@"Authorization"];
    }
    req.HTTPBody = body;
    NSHTTPURLResponse *resp = nil;
    NSData *respBody = [self.httpClient sendSynchronousRequest:req
                                                       options:nil
                                                      response:&resp
                                                         error:nil];
    if (!respBody) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:respBody options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (NSString *)localMeshJelczBase {
    for (NSDictionary *node in self.meshNodes) {
        if (![node isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if ([node[@"name"] isEqualToString:self.nodeName] && [node[@"jelcz"] length] > 0) {
            return node[@"jelcz"];
        }
    }
    return self.publicBaseURL;
}

/**
 Offer local CA bytes to the iroh sidecar and ask mesh peers to pull them.
 Runs on a background queue so Peer & play / playback stay responsive.
 */
- (void)syndicateCIDToMeshAsync:(NSString *)cidStr bytes:(NSData *)bytes {
    if (cidStr.length == 0 || self.meshNodes.count == 0) {
        return;
    }
    NSData *payload = bytes;
    if (payload.length == 0) {
        ATProtoCID *cid = [ATProtoCID daslCIDFromString:cidStr profile:ATProtoDASLCIDProfileBig];
        if (!cid) {
            return;
        }
        payload = [self.objectStore dataForCID:cid error:nil];
    }
    if (payload.length == 0) {
        return;
    }
    NSString *httpsBase = [self localMeshJelczBase];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self refreshIrohPeerRegistryIfConfigured];
        NSDictionary *offer = [self offerBytesToIrohSidecar:payload error:nil];
        NSString *endpointId = offer[@"endpointId"];
        if (endpointId.length == 0) {
            endpointId = self.irohPeerRegistry.localIdentity.endpointId;
        }
        NSString *irohHint = nil;
        if (endpointId.length > 0) {
            irohHint = [NSString stringWithFormat:@"iroh://%@", endpointId];
            [self recordServeMode:@"iroh-offer" bytes:payload.length cid:cidStr note:endpointId];
        }
        NSArray *fanout = [self fanOutCIDToMesh:cidStr
                                   irohProvider:irohHint
                                  httpsProvider:httpsBase];
        for (NSDictionary *row in fanout) {
            if (![row isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *status = row[@"status"] ?: @"";
            NSString *peer = row[@"node"] ?: @"peer";
            NSString *src = row[@"peerSource"] ?: @"";
            NSUInteger size = [row[@"size"] unsignedIntegerValue];
            NSString *note = [NSString stringWithFormat:@"%@ → %@ (%@/%@)",
                              self.nodeName ?: @"jelcz", peer, status,
                              src.length > 0 ? src : @"pull"];
            [self recordServeMode:@"mesh-fanout" bytes:size cid:cidStr note:note];
        }
    });
}

- (NSArray<NSDictionary *> *)fanOutCIDToMesh:(NSString *)cidStr
                                irohProvider:(NSString *)irohProvider
                               httpsProvider:(NSString *)httpsProvider {
    NSMutableArray *out = [NSMutableArray array];
    if (cidStr.length == 0) {
        return out;
    }
    NSString *local = self.nodeName ?: @"";
    for (NSDictionary *node in self.meshNodes) {
        if (![node isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = node[@"name"];
        NSString *kind = node[@"kind"] ?: @"jelcz";
        NSString *base = node[@"jelcz"];
        if (name.length == 0 || [name isEqualToString:local]) {
            continue;
        }
        if (![kind isEqualToString:@"jelcz"] || base.length == 0) {
            continue;
        }
        NSDictionary *result = nil;
        NSString *used = nil;
        if (irohProvider.length > 0) {
            result = [self postJSON:@{
                @"cid": cidStr,
                @"provider": irohProvider,
                @"did": @"did:web:jelcz.local",
            } toBase:base path:@"/demo/streamplace/api/pull-peer"];
            used = irohProvider;
        }
        BOOL ok = [result[@"cid"] length] > 0 &&
            ([result[@"status"] isEqualToString:@"peered-verified"] ||
             [result[@"status"] isEqualToString:@"already-local"]);
        if (!ok && httpsProvider.length > 0) {
            result = [self postJSON:@{
                @"cid": cidStr,
                @"provider": httpsProvider,
                @"did": @"did:web:jelcz.local",
            } toBase:base path:@"/demo/streamplace/api/pull-peer"];
            used = httpsProvider;
        }
        NSMutableDictionary *row = [@{
            @"node": name,
            @"provider": used ?: @"",
            @"status": result[@"status"] ?: result[@"error"] ?: @"unreachable",
        } mutableCopy];
        if (result[@"peerSource"]) {
            row[@"peerSource"] = result[@"peerSource"];
        }
        if (result[@"message"]) {
            row[@"message"] = result[@"message"];
        }
        if (result[@"size"]) {
            row[@"size"] = result[@"size"];
        }
        [out addObject:row];
    }
    return out;
}

- (NSDictionary *)meshStatusDictionary {
    [self refreshIrohPeerRegistryIfConfigured];
    NSMutableArray *edges = [NSMutableArray array];
    NSMutableArray *nodes = [NSMutableArray array];
    NSString *localName = self.nodeName ?: @"jelcz";
    GZJelczIrohSidecarPeerRegistry *reg = self.irohPeerRegistry;

    for (NSDictionary *node in self.meshNodes) {
        if (![node isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = node[@"name"] ?: @"?";
        NSMutableDictionary *entry = [@{
            @"name": name,
            @"kind": node[@"kind"] ?: @"jelcz",
            @"local": @([name isEqualToString:localName]),
        } mutableCopy];
        if (node[@"jelcz"]) entry[@"jelcz"] = node[@"jelcz"];
        if (node[@"sidecar"]) entry[@"sidecar"] = node[@"sidecar"];
        if (node[@"ui"]) entry[@"ui"] = node[@"ui"];
        if (reg) {
            for (NSDictionary *resolved in [reg meshTopologyNodes:@[ node ]]) {
                if (resolved[@"irohEndpointId"]) {
                    entry[@"irohEndpointId"] = resolved[@"irohEndpointId"];
                }
            }
        }
        [nodes addObject:entry];
    }

    if (reg && reg.localIdentity) {
        for (GZJelczIrohSidecarPeerIdentity *peer in reg.remoteIdentities) {
            [edges addObject:@{
                @"from": localName,
                @"to": peer.nodeName ?: peer.sidecarURL,
                @"transport": @"iroh",
                @"endpointId": peer.endpointId ?: @"",
            }];
        }
    }

    for (NSString *https in [self effectiveHTTPSProviderBases]) {
        if ([https isEqualToString:self.upstreamBaseURL]) {
            continue;
        }
        NSURL *u = [NSURL URLWithString:https];
        [edges addObject:@{
            @"from": localName,
            @"to": u.host ?: https,
            @"transport": @"https",
        }];
    }

    NSDictionary *local = nil;
    if (reg && reg.localIdentity) {
        local = @{
            @"nodeName": reg.localIdentity.nodeName ?: localName,
            @"sidecarURL": reg.localIdentity.sidecarURL ?: @"",
            @"endpointId": reg.localIdentity.endpointId ?: @"",
        };
    }
    NSMutableArray *remotePeers = [NSMutableArray array];
    for (GZJelczIrohSidecarPeerIdentity *peer in (reg ? reg.remoteIdentities : @[])) {
        [remotePeers addObject:@{
            @"nodeName": peer.nodeName ?: @"",
            @"sidecarURL": peer.sidecarURL ?: @"",
            @"endpointId": peer.endpointId ?: @"",
        }];
    }

    return @{
        @"nodeName": localName,
        @"irohConfigured": @(self.irohSidecarURL.length > 0),
        @"localIroh": local ?: [NSNull null],
        @"irohPeers": remotePeers,
        @"nodes": nodes,
        @"edges": edges,
        @"irohProviders": [self effectiveIrohProviderHints],
        @"httpsProviders": [self effectiveHTTPSProviderBases],
    };
}

- (nullable NSDictionary *)fetchDemoJSONFromBase:(NSString *)base path:(NSString *)path {
    if (base.length == 0) {
        return nil;
    }
    NSString *trimmed = [base stringByTrimmingCharactersInSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", trimmed, path]];
    if (!url) {
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 3.0;
    NSHTTPURLResponse *resp = nil;
    NSData *body = [self.httpClient sendSynchronousRequest:req options:nil response:&resp error:nil];
    if (!body || resp.statusCode != 200) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (NSString *)jelczNodeNameForHost:(NSString *)host {
    if (host.length == 0) {
        return @"";
    }
    for (NSDictionary *node in self.meshNodes) {
        if (![node isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = node[@"name"];
        for (NSString *key in @[ @"jelcz", @"sidecar", @"ui" ]) {
            NSString *raw = node[key];
            if (raw.length == 0) {
                continue;
            }
            NSURL *u = [NSURL URLWithString:raw];
            if ([u.host isEqualToString:host]) {
                return name ?: host;
            }
        }
        if ([name isEqualToString:host]) {
            return name;
        }
    }
    if ([host hasPrefix:@"iroh-"]) {
        return [NSString stringWithFormat:@"jelcz-%@", [host substringFromIndex:5]];
    }
    if ([host hasPrefix:@"jelcz-"]) {
        return host;
    }
    if ([host isEqualToString:@"streamplace"] ||
        [host containsString:@"stream.place"] ||
        [host containsString:@"streamplace"]) {
        return @"streamplace";
    }
    return host;
}

- (NSString *)inferPeerNodeForEvent:(NSDictionary *)event
                      endpointToNode:(NSDictionary *)endpointToNode {
    NSString *mode = event[@"mode"] ?: @"";
    NSString *note = event[@"note"] ?: @"";
    if ([mode isEqualToString:@"iroh-peer"] || [mode isEqualToString:@"iroh-offer"]) {
        NSString *mapped = endpointToNode[note];
        if (mapped.length > 0) {
            return mapped;
        }
    }
    if ([mode isEqualToString:@"mesh-fanout"]) {
        // note looks like "jelcz-a → jelcz-b (peered-verified/iroh-peer)"
        NSRange arrow = [note rangeOfString:@" → "];
        if (arrow.location != NSNotFound) {
            return [self jelczNodeNameForHost:
                    [[note substringToIndex:arrow.location]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
    }
    if ([mode isEqualToString:@"http-peer"] || [mode isEqualToString:@"https-peer"] ||
        [mode containsString:@"proxy"]) {
        NSURL *u = [NSURL URLWithString:note];
        if (u.host.length > 0) {
            return [self jelczNodeNameForHost:u.host];
        }
        if ([note containsString:@"streamplace"] || [note containsString:@"stream.place"]) {
            return @"streamplace";
        }
    }
    if ([mode isEqualToString:@"range-proxy"] || [mode isEqualToString:@"live-proxy"]) {
        return @"streamplace";
    }
    return @"";
}

- (void)addLinkFrom:(NSString *)from
                 to:(NSString *)to
          transport:(NSString *)transport
          linkKeys:(NSMutableSet *)linkKeys
              into:(NSMutableArray *)links {
    if (from.length == 0 || to.length == 0 || [from isEqualToString:to]) {
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", from, to, transport];
    if ([linkKeys containsObject:key]) {
        return;
    }
    [linkKeys addObject:key];
    [links addObject:@{
        @"from": from,
        @"to": to,
        @"transport": transport,
    }];
}

- (NSDictionary *)buildOverwatchSnapshotFetchingRemotes:(BOOL)fetchRemotes {
    NSMutableDictionary *nodesByName = [NSMutableDictionary dictionary];
    NSMutableDictionary *endpointToNode = [NSMutableDictionary dictionary];
    NSMutableArray *links = [NSMutableArray array];
    NSMutableSet *linkKeys = [NSMutableSet set];
    NSMutableArray *events = [NSMutableArray array];

    nodesByName[@"streamplace"] = [@{
        @"id": @"streamplace",
        @"kind": @"origin",
        @"label": [NSURL URLWithString:self.upstreamBaseURL].host ?: @"streamplace",
        @"ui": self.upstreamBaseURL ?: @"",
        @"reachable": @YES,
    } mutableCopy];

    NSArray *configured = self.meshNodes;
    if (configured.count == 0) {
        configured = @[@{
            @"name": self.nodeName ?: @"jelcz",
            @"jelcz": self.publicBaseURL ?: @"",
            @"ui": self.publicBaseURL ?: @"",
            @"kind": @"jelcz",
        }];
    }

    for (NSDictionary *cfg in configured) {
        if (![cfg isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = cfg[@"name"] ?: @"jelcz";
        NSString *jelczBase = cfg[@"jelcz"] ?: cfg[@"ui"];
        NSString *ui = cfg[@"ui"] ?: jelczBase ?: @"";
        NSMutableDictionary *node = [@{
            @"id": name,
            @"kind": cfg[@"kind"] ?: @"jelcz",
            @"label": name,
            @"ui": ui,
            @"jelcz": jelczBase ?: @"",
            @"sidecar": cfg[@"sidecar"] ?: @"",
            @"reachable": @NO,
        } mutableCopy];

        NSDictionary *stats = nil;
        NSDictionary *mesh = nil;
        BOOL isLocal = [name isEqualToString:self.nodeName];
        if (isLocal) {
            stats = [self allowlistedStatsDictionary];
            mesh = stats[@"mesh"];
        } else if (fetchRemotes && jelczBase.length > 0) {
            stats = [self fetchDemoJSONFromBase:jelczBase path:@"/demo/streamplace/api/stats"];
            mesh = [stats isKindOfClass:[NSDictionary class]] ? stats[@"mesh"] : nil;
        }
        if (stats) {
            node[@"reachable"] = @YES;
            node[@"peeredObjectCount"] = stats[@"peeredObjectCount"] ?: @0;
            node[@"localServeCount"] = stats[@"localServeCount"] ?: @0;
            node[@"proxyServeCount"] = stats[@"proxyServeCount"] ?: @0;
            node[@"proxiedByteCount"] = stats[@"proxiedByteCount"] ?: @0;
            for (NSDictionary *ev in stats[@"recentServes"] ?: @[]) {
                if (![ev isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                NSMutableDictionary *entry = [ev mutableCopy];
                entry[@"node"] = name;
                entry[@"toNode"] = name;
                [events addObject:entry];
            }
        }
        if (mesh) {
            id local = mesh[@"localIroh"];
            if ([local isKindOfClass:[NSDictionary class]] && [local[@"endpointId"] length] > 0) {
                node[@"irohEndpointId"] = local[@"endpointId"];
                endpointToNode[local[@"endpointId"]] = name;
            }
            for (NSDictionary *peer in mesh[@"irohPeers"] ?: @[]) {
                if (![peer isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                NSString *ep = peer[@"endpointId"];
                NSString *peerName = peer[@"nodeName"];
                if (ep.length > 0) {
                    endpointToNode[ep] = [self jelczNodeNameForHost:peerName ?: @""] ?: peerName;
                }
            }
            for (NSDictionary *edge in mesh[@"edges"] ?: @[]) {
                if (![edge isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                NSString *from = [self jelczNodeNameForHost:edge[@"from"] ?: name];
                NSString *to = [self jelczNodeNameForHost:edge[@"to"] ?: @""];
                [self addLinkFrom:from to:to transport:edge[@"transport"] ?: @"https"
                         linkKeys:linkKeys into:links];
            }
        }
        nodesByName[name] = node;
    }

    for (NSMutableDictionary *entry in events) {
        NSString *mode = entry[@"mode"] ?: @"";
        if ([mode isEqualToString:@"mesh-fanout"]) {
            NSString *note = entry[@"note"] ?: @"";
            NSRange arrow = [note rangeOfString:@" → "];
            if (arrow.location != NSNotFound) {
                NSString *fromRaw = [[note substringToIndex:arrow.location]
                                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString *rest = [note substringFromIndex:arrow.location + arrow.length];
                NSString *toRaw = [[rest componentsSeparatedByString:@" "] firstObject];
                NSString *fromNode = [self jelczNodeNameForHost:fromRaw];
                NSString *toNode = [self jelczNodeNameForHost:toRaw];
                if (fromNode.length > 0) entry[@"fromNode"] = fromNode;
                if (toNode.length > 0) entry[@"toNode"] = toNode;
                NSString *transport = [note containsString:@"iroh-peer"] ? @"iroh" :
                    ([note containsString:@"http-peer"] ? @"http" : @"https");
                if (fromNode.length > 0 && toNode.length > 0) {
                    [self addLinkFrom:fromNode to:toNode transport:transport
                             linkKeys:linkKeys into:links];
                }
            }
            continue;
        }
        NSString *fromNode = [self inferPeerNodeForEvent:entry endpointToNode:endpointToNode];
        if (fromNode.length > 0) {
            entry[@"fromNode"] = fromNode;
        }
        if ([mode isEqualToString:@"iroh-peer"] && fromNode.length > 0) {
            [self addLinkFrom:fromNode to:entry[@"node"] transport:@"iroh"
                     linkKeys:linkKeys into:links];
        } else if ([mode isEqualToString:@"http-peer"] && fromNode.length > 0) {
            [self addLinkFrom:fromNode to:entry[@"node"] transport:@"http"
                     linkKeys:linkKeys into:links];
        } else if ([mode isEqualToString:@"https-peer"] && fromNode.length > 0) {
            [self addLinkFrom:fromNode to:entry[@"node"] transport:@"https"
                     linkKeys:linkKeys into:links];
        } else if ([mode containsString:@"proxy"] && fromNode.length > 0) {
            [self addLinkFrom:fromNode to:entry[@"node"] transport:@"https"
                     linkKeys:linkKeys into:links];
        }
    }

    [events sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *ma = a[@"mode"] ?: @"";
        NSString *mb = b[@"mode"] ?: @"";
        BOOL aPeer = [ma isEqualToString:@"iroh-peer"] || [ma isEqualToString:@"iroh-offer"] ||
            [ma isEqualToString:@"http-peer"] || [ma isEqualToString:@"https-peer"] ||
            [ma isEqualToString:@"mesh-fanout"] ||
            [ma isEqualToString:@"ca-seed"] || [ma isEqualToString:@"ca-store"];
        BOOL bPeer = [mb isEqualToString:@"iroh-peer"] || [mb isEqualToString:@"iroh-offer"] ||
            [mb isEqualToString:@"http-peer"] || [mb isEqualToString:@"https-peer"] ||
            [mb isEqualToString:@"mesh-fanout"] ||
            [mb isEqualToString:@"ca-seed"] || [mb isEqualToString:@"ca-store"];
        if (aPeer != bPeer) {
            return aPeer ? NSOrderedAscending : NSOrderedDescending;
        }
        double ta = [a[@"ts"] doubleValue];
        double tb = [b[@"ts"] doubleValue];
        if (ta == tb) return NSOrderedSame;
        return ta > tb ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (events.count > 48) {
        events = [[events subarrayWithRange:NSMakeRange(0, 48)] mutableCopy];
    }

    return @{
        @"viewerNode": self.nodeName ?: @"jelcz",
        @"generatedAt": @([[NSDate date] timeIntervalSince1970]),
        @"upstream": self.upstreamBaseURL ?: @"",
        @"nodes": nodesByName.allValues,
        @"links": links,
        @"events": events,
    };
}

- (NSDictionary *)overwatchSnapshotDictionary {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [self.lock lock];
    NSDictionary *cached = self.cachedOverwatchSnapshot;
    BOOL stale = !cached || (now - self.cachedOverwatchAt) >= 2.0;
    BOOL kick = stale && !self.overwatchRefreshInFlight;
    if (kick) {
        self.overwatchRefreshInFlight = YES;
    }
    [self.lock unlock];

    if (!cached) {
        cached = [self buildOverwatchSnapshotFetchingRemotes:NO];
        [self.lock lock];
        self.cachedOverwatchSnapshot = cached;
        self.cachedOverwatchAt = now;
        [self.lock unlock];
    }

    if (kick) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSDictionary *full = [self buildOverwatchSnapshotFetchingRemotes:YES];
            [self.lock lock];
            self.cachedOverwatchSnapshot = full;
            self.cachedOverwatchAt = [[NSDate date] timeIntervalSince1970];
            self.overwatchRefreshInFlight = NO;
            [self.lock unlock];
        });
    }
    return cached;
}

- (NSArray<NSString *> *)effectiveHTTPSProviderBases {
    return [GZJelczPeerProviderIndex httpsProviderBasesWithBootstrap:self.upstreamBaseURL
                                                        envPeerBases:self.peerHTTPSProviders
                                                       originEntries:self.originEntries
                                                    allowedStreamers:self.allowedStreamers
                                                 allowedBroadcasters:self.allowedBroadcasters];
}

- (NSDictionary *)pullPeerCID:(NSString *)cidStr
                     provider:(NSString *)provider
                          did:(NSString *)did
                        error:(NSError **)error {
    if (cidStr.length == 0 || provider.length == 0) {
        return @{@"error": @"InvalidRequest", @"message": @"bad provider or cid"};
    }
    ATProtoCID *cid = [ATProtoCID daslCIDFromString:cidStr profile:ATProtoDASLCIDProfileBig];
    if (!cid) {
        return @{@"error": @"InvalidRequest", @"message": @"Invalid cid"};
    }
    NSString *irohEndpointId =
        [GZJelczIrohSidecarBlobFetcher endpointIdFromIrohProviderHint:provider];
    if (irohEndpointId.length > 0) {
        [self refreshIrohPeerRegistryIfConfigured];
        if (self.irohSidecarURL.length == 0 || ![self isKnownIrohEndpointId:irohEndpointId]) {
            return @{@"error": @"ProviderNotAllowed", @"message": @"iroh provider is not configured"};
        }
    } else {
        NSString *base = [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:provider];
        if (base.length == 0) {
            return @{@"error": @"InvalidRequest", @"message": @"bad provider or cid"};
        }
        if (![[NSSet setWithArray:[self effectiveHTTPSProviderBases]] containsObject:base]) {
            return @{@"error": @"ProviderNotAllowed", @"message": @"HTTPS provider is not configured"};
        }
    }
    NSDictionary *local = [self.objectStore statCID:cid error:nil];
    if (local) {
        return @{
            @"cid": cidStr,
            @"status": @"already-local",
            @"size": local[@"size"] ?: @0,
            @"peerSource": @"ca-store",
            @"provider": provider,
        };
    }

    if (irohEndpointId.length > 0 && self.irohSidecarURL.length > 0) {
        GZJelczIrohSidecarBlobFetcher *irohFetcher =
            [[GZJelczIrohSidecarBlobFetcher alloc] initWithHTTPClient:self.httpClient
                                                       sidecarBaseURL:self.irohSidecarURL
                                                             trustLan:self.irohSidecarTrustLan];
        irohFetcher.capabilityToken = self.irohSidecarCapabilityToken;
        if (self.irohPeerRegistry) {
            NSMutableDictionary *tickets = [NSMutableDictionary dictionary];
            for (GZJelczIrohSidecarPeerIdentity *peer in self.irohPeerRegistry.remoteIdentities) {
                if (peer.endpointId.length > 0 && peer.endpointTicket.length > 0) {
                    tickets[peer.endpointId] = peer.endpointTicket;
                }
            }
            irohFetcher.endpointTicketsByEndpointId = tickets;
        }
        irohFetcher.defaultProviderEndpointId = self.irohBootstrapEndpointId;
        irohFetcher.defaultProviderEndpointTicket = self.irohBootstrapEndpointTicket;
        ATProtoCAMirrorResolver *resolver =
            [[ATProtoCAMirrorResolver alloc] initWithObjectStore:self.objectStore fetcher:irohFetcher];
        resolver.mirrorFetchEnabled = YES;
        NSError *fetchErr = nil;
        NSData *bytes = [resolver dataForCID:cid providers:@[ provider ] error:&fetchErr];
        if (!bytes) {
            if (error && fetchErr) *error = fetchErr;
            return @{
                @"error": @"PullFailed",
                @"message": fetchErr.localizedDescription ?: @"iroh peer fetch failed",
                @"provider": provider,
            };
        }
        self.peeredObjectCount += 1;
        [self recordServeMode:@"iroh-peer" bytes:bytes.length cid:cidStr note:irohEndpointId];
        return @{
            @"cid": cidStr,
            @"status": @"peered-verified",
            @"size": @(bytes.length),
            @"peerSource": @"iroh-peer",
            @"provider": provider,
            @"blake3Verified": @YES,
        };
    }

    NSString *base = [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:provider];
    if (base.length == 0) {
        return @{@"error": @"InvalidRequest", @"message": @"bad provider or cid"};
    }
    GZJelczStreamplaceBlobFetcher *fetcher =
        [[GZJelczStreamplaceBlobFetcher alloc] initWithHTTPClient:self.httpClient
                                                 attributionDID:did];
    ATProtoCAMirrorResolver *resolver =
        [[ATProtoCAMirrorResolver alloc] initWithObjectStore:self.objectStore fetcher:fetcher];
    resolver.mirrorFetchEnabled = YES;
    NSError *fetchErr = nil;
    NSData *bytes = [resolver dataForCID:cid providers:@[ base ] error:&fetchErr];
    if (!bytes) {
        if (error && fetchErr) *error = fetchErr;
        return @{
            @"error": @"PullFailed",
            @"message": fetchErr.localizedDescription ?: @"peer fetch failed",
            @"provider": base,
        };
    }
    NSString *peerSource = GZJelczDemoPeerSourceForHTTPBase(base);
    self.peeredObjectCount += 1;
    [self recordServeMode:peerSource bytes:bytes.length cid:cidStr note:base];
    return @{
        @"cid": cidStr,
        @"status": @"peered-verified",
        @"size": @(bytes.length),
        @"peerSource": peerSource,
        @"provider": base,
        @"blake3Verified": @YES,
    };
}

- (void)recordServeMode:(NSString *)mode
                  bytes:(NSUInteger)bytes
                    cid:(NSString *)cid
                   note:(NSString *)note {
    if (mode.length == 0) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *entry = [@{
        @"ts": @(now),
        @"mode": mode,
        @"bytes": @(bytes),
        @"via": @"jelcz",
    } mutableCopy];
    if (cid.length > 0) entry[@"cid"] = cid;
    if (note.length > 0) entry[@"note"] = note;
    [self.lock lock];
    // Range-proxy / live-proxy spam fills the feed and hides iroh peership.
    // Keep at most one sample per CID within ~1.5s for those modes.
    if ([mode isEqualToString:@"range-proxy"] || [mode isEqualToString:@"live-proxy"]) {
        NSDictionary *head = self.recentServes.firstObject;
        if ([head[@"mode"] isEqualToString:mode] &&
            cid.length > 0 &&
            [head[@"cid"] isEqualToString:cid] &&
            (now - [head[@"ts"] doubleValue]) < 1.5) {
            NSMutableDictionary *merged = [head mutableCopy];
            merged[@"ts"] = @(now);
            merged[@"bytes"] = @([head[@"bytes"] unsignedIntegerValue] + bytes);
            merged[@"note"] = note.length > 0 ? note : head[@"note"];
            merged[@"samples"] = @([head[@"samples"] unsignedIntegerValue] + 1);
            self.recentServes[0] = [merged copy];
            [self.lock unlock];
            return;
        }
    }
    [self.recentServes insertObject:[entry copy] atIndex:0];
    while (self.recentServes.count > kDemoRecentServeLimit) {
        [self.recentServes removeLastObject];
    }
    [self.lock unlock];
}

- (NSDictionary *)allowlistedStatsDictionary {
    [self.lock lock];
    NSArray *recent = [self.recentServes copy] ?: @[];
    NSUInteger sessions = self.peerSessions.count;
    [self.lock unlock];
    return @{
        @"peeredObjectCount": @(self.peeredObjectCount),
        @"proxiedByteCount": @(self.proxiedByteCount),
        @"localServeCount": @(self.localServeCount),
        @"proxyServeCount": @(self.proxyServeCount),
        @"fullPeerMaxBytes": @(self.fullPeerMaxBytes),
        @"upstreamHost": [NSURL URLWithString:self.upstreamBaseURL].host ?: @"",
        @"browserOrigin": self.publicBaseURL ?: @"",
        @"sessionCount": @(sessions),
        @"browserTalksToStreamplace": @NO,
        @"peership": @{
            @"model": @"VOD: getVideoBlob→CA/range-proxy; Live: getLiveSegment via jelcz; WS16 HTTPS peers",
            @"browserOrigin": self.publicBaseURL ?: @"",
            @"upstreamDiscoveryOnly": self.upstreamBaseURL ?: @"",
        },
        @"recentServes": recent,
        @"httpsProviders": [self effectiveHTTPSProviderBases],
        @"originEntryCount": @(self.originEntries.count),
        @"consent": @{
            @"allowedStreamers": self.allowedStreamers.allObjects ?: @[],
            @"allowedBroadcasters": self.allowedBroadcasters.allObjects ?: @[],
            @"autoIngestOrigins": @((self.allowedStreamers.count + self.allowedBroadcasters.count) > 0),
        },
        @"originAnnounceConfigured": @(self.originAnnouncer != nil),
        @"nodeName": self.nodeName ?: @"jelcz",
        @"mesh": [self meshStatusDictionary],
    };
}

#pragma mark - HTTP helpers

- (NSData *)upstreamGET:(NSString *)pathOrURL
            rangeHeader:(NSString *)rangeHeader
               response:(NSHTTPURLResponse **)outResponse
                  error:(NSError **)error {
    NSString *urlString = pathOrURL;
    if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
        if (![urlString hasPrefix:@"/"]) {
            urlString = [@"/" stringByAppendingString:urlString];
        }
        urlString = [self.upstreamBaseURL stringByAppendingString:urlString];
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bad upstream URL"}];
        }
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 45.0;
    if (rangeHeader.length > 0) {
        [req setValue:rangeHeader forHTTPHeaderField:@"Range"];
    }

    // NSURLSession for outbound discovery/proxy (avoid SafeHTTPClient sync on
    // the HTTP handler queue).
    __block NSData *body = nil;
    __block NSHTTPURLResponse *resp = nil;
    __block NSError *reqError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 45.0;
    cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"jelcz-streamplace-peer-demo/1.0" };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithRequest:req
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *taskError) {
                    body = data;
                    resp = (NSHTTPURLResponse *)response;
                    reqError = taskError;
                    dispatch_semaphore_signal(sema);
                    [session finishTasksAndInvalidate];
                }] resume];
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_SEC))) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Upstream request timed out"}];
        }
        return nil;
    }
    if (outResponse) *outResponse = resp;
    if (error && reqError) *error = reqError;
    return reqError ? nil : body;
}

- (void)writeJSON:(id)obj status:(NSInteger)status response:(ATProtoHttpResponse *)response {
    response.statusCode = status;
    response.statusMessage = [ATProtoHttpResponse defaultMessageForCode:(HttpStatusCode)status];
    response.contentType = @"application/json; charset=utf-8";
    [response setHeader:@"no-store" forKey:@"Cache-Control"];
    [response setJsonBody:obj];
}

/**
 The demo is public for inspection.  Setting apiToken at composition time turns
 mutation endpoints into a capability boundary without making local demos
 require credentials.  Keep the token out of responses and logs.
 */
- (BOOL)authorizeMutationRequest:(ATProtoHttpRequest *)request
                        response:(ATProtoHttpResponse *)response {
    if (self.apiToken.length == 0) {
        return YES;
    }
    NSString *authorization = [request headerForKey:@"Authorization"];
    if (authorization.length == 0) {
        [response setHeader:@"Bearer realm=\"jelcz-demo\"" forKey:@"WWW-Authenticate"];
        [self writeJSON:@{@"error": @"Unauthorized", @"message": @"demo mutation capability required"}
                     status:401
                   response:response];
        return NO;
    }
    if (![authorization hasPrefix:@"Bearer "] ||
        ![PDSSecurityCompare constantTimeEqualString:[authorization substringFromIndex:7]
                                              string:self.apiToken]) {
        [self writeJSON:@{@"error": @"Forbidden", @"message": @"invalid demo mutation capability"}
                     status:403
                   response:response];
        return NO;
    }
    return YES;
}

- (nullable id)boundedMutationJSONForRequest:(ATProtoHttpRequest *)request
                                     response:(ATProtoHttpResponse *)response {
    if (request.body.length == 0) {
        [self writeJSON:@{@"error": @"InvalidRequest", @"message": @"JSON body required"}
                     status:400
                   response:response];
        return nil;
    }
    if (request.body.length > self.mutationJSONMaxBytes) {
        [self writeJSON:@{@"error": @"PayloadTooLarge", @"message": @"JSON body exceeds demo limit"}
                     status:413
                   response:response];
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:request.body options:0 error:nil];
    if (!json) {
        [self writeJSON:@{@"error": @"InvalidRequest", @"message": @"invalid JSON body"}
                     status:400
                   response:response];
    }
    return json;
}

- (nullable NSDictionary *)boundedMutationJSONDictionaryForRequest:(ATProtoHttpRequest *)request
                                                            response:(ATProtoHttpResponse *)response {
    id json = [self boundedMutationJSONForRequest:request response:response];
    if (!json) {
        return nil;
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
        [self writeJSON:@{@"error": @"InvalidRequest", @"message": @"JSON object required"}
                     status:400
                   response:response];
        return nil;
    }
    return json;
}

- (BOOL)isKnownIrohEndpointId:(NSString *)endpointId {
    if (endpointId.length == 0) {
        return NO;
    }
    if ([endpointId isEqualToString:self.irohBootstrapEndpointId]) {
        return YES;
    }
    if ([self.irohPeerRegistry.localIdentity.endpointId isEqualToString:endpointId]) {
        return YES;
    }
    for (GZJelczIrohSidecarPeerIdentity *peer in self.irohPeerRegistry.remoteIdentities) {
        if ([peer.endpointId isEqualToString:endpointId]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Catalog

- (NSArray *)fetchLiveStreams:(NSError **)error {
    NSHTTPURLResponse *resp = nil;
    NSData *body = [self upstreamGET:@"/xrpc/place.stream.live.getLiveUsers?limit=24"
                         rangeHeader:nil
                            response:&resp
                               error:error];
    if (!body || resp.statusCode != 200) {
        return @[];
    }
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    NSArray *streams = [json isKindOfClass:[NSDictionary class]] ? json[@"streams"] : nil;
    if (![streams isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *s in streams) {
        if (![s isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *author = s[@"author"];
        NSDictionary *record = s[@"record"];
        NSDictionary *viewer = s[@"viewerCount"];
        [out addObject:@{
            @"kind": @"live",
            @"uri": s[@"uri"] ?: [NSNull null],
            @"title": record[@"title"] ?: @"Untitled live",
            @"did": author[@"did"] ?: [NSNull null],
            @"handle": author[@"handle"] ?: [NSNull null],
            @"viewers": viewer[@"count"] ?: @0,
            @"indexedAt": s[@"indexedAt"] ?: [NSNull null],
            @"thumbCid": record[@"thumb"][@"ref"][@"$link"] ?: [NSNull null],
                        @"streamplaceURL": record[@"url"] ?: [NSNull null],
            @"peerable": @YES,
        }];
    }
    return out;
}

- (NSArray *)fetchSampleVODs:(NSError **)error {
    // Known Streamplace creator with public place.stream.video records.
    NSString *did = @"did:plc:rbvrr34edl5ddpuwcubjiost";
    NSHTTPURLResponse *plcResp = nil;
    NSData *plcBody = [self upstreamGET:
                       [NSString stringWithFormat:@"https://plc.directory/%@", did]
                            rangeHeader:nil
                               response:&plcResp
                                  error:error];
    NSString *pds = nil;
    if (plcBody) {
        id plc = [NSJSONSerialization JSONObjectWithData:plcBody options:0 error:nil];
        for (NSDictionary *svc in plc[@"service"] ?: @[]) {
            if ([svc[@"type"] isEqualToString:@"AtprotoPersonalDataServer"]) {
                pds = svc[@"serviceEndpoint"];
                break;
            }
        }
    }
    if (pds.length == 0) {
        pds = @"https://iameli.com";
    }
    NSString *listPath =
        [NSString stringWithFormat:
         @"%@/xrpc/com.atproto.repo.listRecords?repo=%@&collection=place.stream.video&limit=12",
         [pds stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]],
         did];
    NSHTTPURLResponse *resp = nil;
    NSData *body = [self upstreamGET:listPath rangeHeader:nil response:&resp error:error];
    if (!body || resp.statusCode != 200) {
        return @[];
    }
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    NSArray *records = [json isKindOfClass:[NSDictionary class]] ? json[@"records"] : nil;
    if (![records isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *row in records) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *value = row[@"value"];
        [out addObject:@{
            @"kind": @"vod",
            @"uri": row[@"uri"] ?: [NSNull null],
            @"title": value[@"title"] ?: @"Untitled VOD",
            @"did": did,
            @"durationMs": value[@"durationMs"] ?: [NSNull null],
            @"createdAt": value[@"createdAt"] ?: [NSNull null],
            @"thumbCid": value[@"thumb"][@"ref"][@"$link"] ?: [NSNull null],
            @"peerable": @YES,
        }];
    }
    return out;
}

#pragma mark - Peership

- (NSString *)stripM4S:(NSString *)cid {
    if ([cid.lowercaseString hasSuffix:@".m4s"]) {
        return [cid substringToIndex:cid.length - 4];
    }
    return cid;
}

- (NSString *)vodOriginBase {
    return self.vodOriginBaseURL.length > 0 ? self.vodOriginBaseURL : self.upstreamBaseURL;
}

- (NSData *)vodGET:(NSString *)pathOrURL
       rangeHeader:(NSString *)rangeHeader
          response:(NSHTTPURLResponse **)outResponse
             error:(NSError **)error {
    NSString *urlString = pathOrURL;
    if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
        if (![urlString hasPrefix:@"/"]) {
            urlString = [@"/" stringByAppendingString:urlString];
        }
        urlString = [[self vodOriginBase] stringByAppendingString:urlString];
    }
    return [self upstreamGET:urlString rangeHeader:rangeHeader response:outResponse error:error];
}

- (unsigned long long)probeObjectSizeForCID:(NSString *)cid
                                        did:(NSString *)did
                                      error:(NSError **)error {
    NSString *path = [NSString stringWithFormat:
                      @"/xrpc/place.stream.playback.getVideoBlob?did=%@&cid=%@",
                      [did stringByAddingPercentEncodingWithAllowedCharacters:
                       [NSCharacterSet URLQueryAllowedCharacterSet]] ?: did,
                      [cid stringByAddingPercentEncodingWithAllowedCharacters:
                       [NSCharacterSet URLQueryAllowedCharacterSet]] ?: cid];
    NSHTTPURLResponse *resp = nil;
    NSData *body = [self vodGET:path rangeHeader:@"bytes=0-0" response:&resp error:error];
    (void)body;
    NSString *cr = resp.allHeaderFields[@"Content-Range"] ?: resp.allHeaderFields[@"content-range"];
    if ([cr isKindOfClass:[NSString class]]) {
        NSRange slash = [cr rangeOfString:@"/" options:NSBackwardsSearch];
        if (slash.location != NSNotFound) {
            return (unsigned long long)[[cr substringFromIndex:slash.location + 1] longLongValue];
        }
    }
    if (resp.statusCode == 200) {
        return (unsigned long long)(body.length);
    }
    return 0;
}

- (NSDictionary *)peerVODURI:(NSString *)uri error:(NSError **)error {
    if (uri.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"uri required"}];
        }
        return nil;
    }
    NSString *enc = nil;
    {
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
        enc = [uri stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: uri;
    }
    NSString *playlistPath =
        [NSString stringWithFormat:@"/xrpc/place.stream.playback.getVideoPlaylist?uri=%@", enc];
    NSHTTPURLResponse *masterResp = nil;
    NSData *masterData = [self vodGET:playlistPath rangeHeader:nil response:&masterResp error:error];
    if (!masterData || masterResp.statusCode != 200) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:3
                                     userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:
                     @"Failed to fetch master playlist (HTTP %ld from %@)",
                     (long)masterResp.statusCode, [self vodOriginBase]]
            }];
        }
        return nil;
    }
    NSString *master = [[NSString alloc] initWithData:masterData encoding:NSUTF8StringEncoding] ?: @"";
    // Prefer first video track playlist.
    NSRegularExpression *trackRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"/xrpc/place\\.stream\\.playback\\.getVideoPlaylist\\?[^\\s\"]+track=1[^\\s\"]*"
                                                 options:0
                                                   error:nil];
    NSTextCheckingResult *m = [trackRe firstMatchInString:master options:0 range:NSMakeRange(0, master.length)];
    NSString *mediaPath = nil;
    if (m) {
        mediaPath = [master substringWithRange:m.range];
    } else {
        mediaPath = playlistPath;
    }
    NSHTTPURLResponse *mediaResp = nil;
    NSData *mediaData = [self vodGET:mediaPath rangeHeader:nil response:&mediaResp error:error];
    if (!mediaData || mediaResp.statusCode != 200) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch media playlist"}];
        }
        return nil;
    }
    NSString *media = [[NSString alloc] initWithData:mediaData encoding:NSUTF8StringEncoding] ?: @"";
    NSRegularExpression *cidRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"getVideoBlob\\?[^\\s\"]*cid=(bafkr4i[a-z0-9]+)(?:\\.m4s)?"
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:nil];
    NSRegularExpression *didRe =
        [NSRegularExpression regularExpressionWithPattern:@"did=([^&\"\\s]+)"
                                                 options:0
                                                   error:nil];
    NSMutableSet *cids = [NSMutableSet set];
    NSString *attributionDID = nil;
    [cidRe enumerateMatchesInString:media
                            options:0
                              range:NSMakeRange(0, media.length)
                         usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                             (void)flags; (void)stop;
                             if (result.numberOfRanges >= 2) {
                                 [cids addObject:[media substringWithRange:[result rangeAtIndex:1]]];
                             }
                         }];
    NSTextCheckingResult *didMatch = [didRe firstMatchInString:media options:0 range:NSMakeRange(0, media.length)];
    if (didMatch.numberOfRanges >= 2) {
        attributionDID = [[media substringWithRange:[didMatch rangeAtIndex:1]]
                          stringByRemovingPercentEncoding] ?: [media substringWithRange:[didMatch rangeAtIndex:1]];
    }
    if (attributionDID.length == 0) {
        // Fall back to AT-URI authority.
        if ([uri hasPrefix:@"at://"]) {
            NSArray *parts = [[uri substringFromIndex:5] componentsSeparatedByString:@"/"];
            if (parts.count > 0) attributionDID = parts[0];
        }
    }

    GZJelczStreamplaceBlobFetcher *fetcher =
        [[GZJelczStreamplaceBlobFetcher alloc] initWithHTTPClient:self.httpClient
                                                  attributionDID:attributionDID ?: @"did:web:stream.place"];
    ATProtoCAMirrorResolver *resolver =
        [[ATProtoCAMirrorResolver alloc] initWithObjectStore:self.objectStore fetcher:fetcher];
    resolver.mirrorFetchEnabled = YES;

    NSMutableArray *objects = [NSMutableArray array];
    for (NSString *rawCid in cids) {
        NSString *cidStr = [self stripM4S:rawCid];
        ATProtoCID *cid = [ATProtoCID daslCIDFromString:cidStr profile:ATProtoDASLCIDProfileBig];
        if (!cid) {
            [objects addObject:@{@"cid": cidStr, @"status": @"invalid-cid"}];
            continue;
        }
        NSError *probeErr = nil;
        unsigned long long size = [self probeObjectSizeForCID:cidStr did:attributionDID error:&probeErr];
        NSDictionary *localStat = [self.objectStore statCID:cid error:nil];
        if (localStat) {
            self.peeredObjectCount += 1;
            [objects addObject:@{
                @"cid": cidStr,
                @"status": @"already-local",
                @"size": localStat[@"size"] ?: @(size),
                @"mode": @"ca-store",
            }];
            [self syndicateCIDToMeshAsync:cidStr bytes:nil];
            continue;
        }
        if (size > 0 && size <= self.fullPeerMaxBytes) {
            NSError *fetchErr = nil;
            NSData *bytes = [resolver dataForCID:cid
                                       providers:@[ [self vodOriginBase] ]
                                           error:&fetchErr];
            if (bytes) {
                self.peeredObjectCount += 1;
                [objects addObject:@{
                    @"cid": cidStr,
                    @"status": @"peered-verified",
                    @"size": @(bytes.length),
                    @"mode": @"ca-store",
                    @"blake3Verified": @YES,
                    @"meshSyndicate": @YES,
                }];
                [self syndicateCIDToMeshAsync:cidStr bytes:bytes];
            } else {
                [objects addObject:@{
                    @"cid": cidStr,
                    @"status": @"peer-failed",
                    @"size": @(size),
                    @"error": fetchErr.localizedDescription ?: @"fetch failed",
                }];
            }
        } else {
            [objects addObject:@{
                @"cid": cidStr,
                @"status": @"range-proxy",
                @"size": @(size),
                @"mode": @"jelcz-range-proxy",
                @"reason": @"Object exceeds fullPeerMaxBytes; playback Ranges flow through jelcz",
            }];
        }
    }

    NSString *sessionId = [[NSUUID UUID] UUIDString];
    NSString *localPlaylistURL =
        [NSString stringWithFormat:@"%@/demo/streamplace/playlist?uri=%@",
         self.publicBaseURL, enc];
    NSDictionary *session = @{
        @"sessionId": sessionId,
        @"uri": uri,
        @"attributionDID": attributionDID ?: [NSNull null],
        @"objects": objects,
        @"localPlaylistURL": localPlaylistURL,
        @"playbackVia": @"jelcz",
        @"browserTalksToStreamplace": @NO,
    };
    [self.lock lock];
    self.peerSessions[sessionId] = session;
    [self.lock unlock];
    return session;
}

- (NSString *)rewritePlaylist:(NSString *)playlist {
    // Point every getVideoBlob URL at this jelcz instance.
    NSString *replacement =
        [NSString stringWithFormat:@"%@/xrpc/place.stream.playback.getVideoBlob", self.publicBaseURL];
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"https?://[^/]+/xrpc/place\\.stream\\.playback\\.getVideoBlob"
                                                 options:0
                                                   error:nil];
    NSString *out = [re stringByReplacingMatchesInString:playlist
                                                 options:0
                                                   range:NSMakeRange(0, playlist.length)
                                            withTemplate:replacement];
    // Relative Streamplace paths → absolute jelcz XRPC (blob) or local playlist proxy.
    out = [out stringByReplacingOccurrencesOfString:
           @"/xrpc/place.stream.playback.getVideoBlob"
                                         withString:
           [NSString stringWithFormat:@"%@/xrpc/place.stream.playback.getVideoBlob", self.publicBaseURL]];
    out = [out stringByReplacingOccurrencesOfString:
           @"/xrpc/place.stream.playback.getVideoPlaylist"
                                         withString:
           [NSString stringWithFormat:@"%@/demo/streamplace/playlist", self.publicBaseURL]];
    return out;
}

- (NSString *)rewriteLivePlaylist:(NSString *)playlist {
    NSString *pl =
        [NSString stringWithFormat:@"%@/demo/streamplace/live/playlist", self.publicBaseURL];
    NSString *seg =
        [NSString stringWithFormat:@"%@/demo/streamplace/live/segment", self.publicBaseURL];
    NSRegularExpression *plAbs =
        [NSRegularExpression regularExpressionWithPattern:
         @"https?://[^/\\s\"]+/xrpc/place\\.stream\\.playback\\.getLivePlaylist"
                                                 options:0
                                                   error:nil];
    NSRegularExpression *segAbs =
        [NSRegularExpression regularExpressionWithPattern:
         @"https?://[^/\\s\"]+/xrpc/place\\.stream\\.playback\\.getLiveSegment"
                                                 options:0
                                                   error:nil];
    NSString *out = [plAbs stringByReplacingMatchesInString:playlist
                                                    options:0
                                                      range:NSMakeRange(0, playlist.length)
                                               withTemplate:pl];
    out = [segAbs stringByReplacingMatchesInString:out
                                           options:0
                                             range:NSMakeRange(0, out.length)
                                      withTemplate:seg];
    out = [out stringByReplacingOccurrencesOfString:
           @"/xrpc/place.stream.playback.getLivePlaylist"
                                         withString:pl];
    out = [out stringByReplacingOccurrencesOfString:
           @"/xrpc/place.stream.playback.getLiveSegment"
                                         withString:seg];
    return out;
}

- (NSString *)percentEncodeQueryValue:(NSString *)value {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

- (NSDictionary *)peerLiveStreamer:(NSString *)streamerDID error:(NSError **)error {
    if (streamerDID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"streamer DID required"}];
        }
        return nil;
    }
    NSString *enc = [self percentEncodeQueryValue:streamerDID];
    NSString *path =
        [NSString stringWithFormat:@"/xrpc/place.stream.playback.getLivePlaylist?streamer=%@", enc];
    NSHTTPURLResponse *resp = nil;
    NSError *upErr = nil;
    NSData *data = [self upstreamGET:path rangeHeader:nil response:&resp error:&upErr];
    if (!data || resp.statusCode != 200) {
        if (error) {
            *error = upErr ?: [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                                  code:3
                                              userInfo:@{NSLocalizedDescriptionKey:
                                                             @"Failed to fetch live playlist"}];
        }
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (![text hasPrefix:@"#EXTM3U"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Upstream live playlist invalid"}];
        }
        return nil;
    }
    NSString *sessionId = [[NSUUID UUID] UUIDString];
    NSString *localPlaylistURL =
        [NSString stringWithFormat:@"%@/demo/streamplace/live/playlist?streamer=%@",
         self.publicBaseURL, enc];
    NSDictionary *session = @{
        @"sessionId": sessionId,
        @"kind": @"live",
        @"streamer": streamerDID,
        @"localPlaylistURL": localPlaylistURL,
        @"playbackVia": @"jelcz",
        @"mode": @"jelcz-live-segment-proxy",
        @"browserTalksToStreamplace": @NO,
    };
    [self.lock lock];
    self.peerSessions[sessionId] = session;
    [self.lock unlock];
    return session;
}

- (BOOL)proxyUpstreamPath:(NSString *)path
              rangeHeader:(NSString *)rangeHeader
                 response:(ATProtoHttpResponse *)response
                    error:(NSError **)error {
    NSHTTPURLResponse *up = nil;
    NSError *upErr = nil;
    NSData *body = [self upstreamGET:path rangeHeader:rangeHeader response:&up error:&upErr];
    if (!body || (up.statusCode != 200 && up.statusCode != 206)) {
        response.statusCode = up.statusCode > 0 ? up.statusCode : 502;
        if (error) *error = upErr;
        return NO;
    }
    self.proxyServeCount += 1;
    self.proxiedByteCount += body.length;
    [self recordServeMode:@"live-proxy" bytes:body.length cid:nil note:@"getLiveSegment"];
    response.statusCode = up.statusCode;
    NSString *ctype = up.MIMEType;
    if (ctype.length == 0) {
        ctype = @"application/octet-stream";
    }
    response.contentType = ctype;
    NSString *cr = up.allHeaderFields[@"Content-Range"] ?: up.allHeaderFields[@"content-range"];
    if (cr) [response setHeader:cr forKey:@"Content-Range"];
    NSString *ar = up.allHeaderFields[@"Accept-Ranges"] ?: up.allHeaderFields[@"accept-ranges"];
    if (ar) [response setHeader:ar forKey:@"Accept-Ranges"];
    [response setHeader:@"live-proxy" forKey:@"X-Jelcz-Peer"];
    [response setBodyData:body];
    return YES;
}

- (nullable NSString *)resolveAssetPath:(NSString *)relativeName {
    NSString *envRoot = [[[NSProcessInfo processInfo] environment] objectForKey:@"JELCZ_DEMO_UI_PATH"];
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    if (envRoot.length > 0) {
        [dirs addObject:[envRoot stringByDeletingLastPathComponent]];
    }
    [dirs addObject:@"Garazyk/Resources/jelcz-demo"];
    [dirs addObject:@"../Garazyk/Resources/jelcz-demo"];
    for (NSString *dir in dirs) {
        NSString *path = [dir stringByAppendingPathComponent:relativeName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (BOOL)serveBlobRequest:(ATProtoHttpRequest *)request
                response:(ATProtoHttpResponse *)response
                   error:(NSError **)error {
    NSString *did = [request queryParamForKey:@"did"];
    NSString *cidParam = [self stripM4S:[request queryParamForKey:@"cid"]];
    if (did.length == 0 || cidParam.length == 0) {
        [self writeJSON:@{@"error": @"InvalidRequest", @"message": @"did and cid required"}
                 status:400
               response:response];
        return NO;
    }
    ATProtoCID *cid = [ATProtoCID daslCIDFromString:cidParam profile:ATProtoDASLCIDProfileBig];
    if (!cid) {
        [self writeJSON:@{@"error": @"InvalidRequest", @"message": @"Invalid cid"}
                 status:400
               response:response];
        return NO;
    }

    // Prefer local CA object (full peer).
    GZJelczStreamplaceCompatServe *local =
        [[GZJelczStreamplaceCompatServe alloc] initWithObjectStore:self.objectStore];
    NSError *localErr = nil;
    if ([local handleRequest:request response:response error:&localErr]) {
        self.localServeCount += 1;
        NSUInteger served = response.body.length;
        if (served == 0 && response.bodyString.length > 0) {
            served = [response.bodyString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        }
        [self recordServeMode:@"ca-store" bytes:served cid:cidParam note:@"local CA hit"];
        [response setHeader:@"ca-store" forKey:@"X-Jelcz-Peer"];
        return YES;
    }
    if (response.statusCode != 404) {
        return NO;
    }

    // Range-proxy from Streamplace — browser never contacts upstream.
    NSString *range = [request headerForKey:@"Range"];
    NSString *path = [NSString stringWithFormat:
                      @"/xrpc/place.stream.playback.getVideoBlob?did=%@&cid=%@",
                      [did stringByAddingPercentEncodingWithAllowedCharacters:
                       [NSCharacterSet URLQueryAllowedCharacterSet]] ?: did,
                      [cidParam stringByAddingPercentEncodingWithAllowedCharacters:
                       [NSCharacterSet URLQueryAllowedCharacterSet]] ?: cidParam];
    NSHTTPURLResponse *up = nil;
    NSError *upErr = nil;
    NSData *body = [self upstreamGET:path rangeHeader:range response:&up error:&upErr];
    if (!body || (up.statusCode != 200 && up.statusCode != 206)) {
        NSString *vodBase = [self vodOriginBase];
        if (![vodBase isEqualToString:self.upstreamBaseURL]) {
            body = [self vodGET:path rangeHeader:range response:&up error:&upErr];
        }
    }
    if (!body || (up.statusCode != 200 && up.statusCode != 206)) {
        [self writeJSON:@{
            @"error": @"BlobNotFound",
            @"message": upErr.localizedDescription ?: @"Upstream miss"
        } status:404 response:response];
        if (error) *error = upErr;
        return NO;
    }
    self.proxyServeCount += 1;
    self.proxiedByteCount += body.length;
    [self recordServeMode:@"range-proxy" bytes:body.length cid:cidParam note:@"upstream via jelcz"];
    response.statusCode = up.statusCode;
    response.contentType = up.MIMEType.length > 0 ? up.MIMEType : @"video/mp4";
    NSString *cr = up.allHeaderFields[@"Content-Range"] ?: up.allHeaderFields[@"content-range"];
    if (cr) [response setHeader:cr forKey:@"Content-Range"];
    [response setHeader:@"bytes" forKey:@"Accept-Ranges"];
    [response setHeader:@"range-proxy" forKey:@"X-Jelcz-Peer"];
    [response setHeader:self.upstreamBaseURL forKey:@"X-Jelcz-Upstream"];
    [response setBodyData:body];
    return YES;
}

- (BOOL)serveBlobForRequest:(ATProtoHttpRequest *)request
                   response:(ATProtoHttpResponse *)response
                      error:(NSError **)error {
    return [self serveBlobRequest:request response:response error:error];
}

#pragma mark - Routes + UI

- (NSString *)loadHTMLNamed:(NSString *)filename fallback:(NSString *)fallbackHTML {
    NSString *dir = [[[NSProcessInfo processInfo] environment] objectForKey:@"JELCZ_DEMO_UI_PATH"];
    if (dir.length > 0) {
        dir = [dir stringByDeletingLastPathComponent];
    }
    NSArray *candidates = @[
        dir.length > 0 ? [dir stringByAppendingPathComponent:filename] : @"",
        [@"Garazyk/Resources/jelcz-demo/" stringByAppendingString:filename],
        [@"../Garazyk/Resources/jelcz-demo/" stringByAppendingString:filename],
    ];
    for (NSString *path in candidates) {
        if (path.length == 0) continue;
        NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (html.length > 0) return html;
    }
    return fallbackHTML;
}

- (NSString *)loadHTML {
    return [self loadHTMLNamed:@"streamplace-peer.html"
                      fallback:@"<!doctype html><meta charset=utf-8><title>jelcz peer demo</title>"
             @"<p>Missing streamplace-peer.html — set JELCZ_DEMO_UI_PATH.</p>"];
}

- (NSString *)loadOverwatchHTML {
    return [self loadHTMLNamed:@"streamplace-overwatch.html"
                      fallback:@"<!doctype html><meta charset=utf-8><title>jelcz overwatch</title>"
             @"<p>Missing streamplace-overwatch.html.</p>"];
}

- (void)writeDemoHTML:(ATProtoHttpResponse *)response {
    response.statusCode = 200;
    response.contentType = @"text/html; charset=utf-8";
    // HLS.js attaches blob: media and may spawn a worker; allow those on this page only.
    [response setHeader:
     @"default-src 'self'; "
     "script-src 'self' 'unsafe-inline'; "
     "style-src 'self' 'unsafe-inline'; "
     "img-src 'self' data:; "
     "media-src 'self' blob:; "
     "worker-src 'self' blob:; "
     "connect-src 'self'; "
     "font-src 'self' data:; "
     "frame-ancestors 'none'; "
     "base-uri 'self'"
                     forKey:@"Content-Security-Policy"];
    [response setBodyString:[self loadHTML]];
}

- (void)writeOverwatchHTML:(ATProtoHttpResponse *)response {
    response.statusCode = 200;
    response.contentType = @"text/html; charset=utf-8";
    [response setHeader:
     @"default-src 'self'; "
     "script-src 'self' 'unsafe-inline'; "
     "style-src 'self' 'unsafe-inline'; "
     "img-src 'self' data:; "
     "connect-src 'self'; "
     "font-src 'self' data:; "
     "frame-ancestors 'none'; "
     "base-uri 'self'"
                     forKey:@"Content-Security-Policy"];
    [response setBodyString:[self loadOverwatchHTML]];
}

- (void)registerRoutesOnServer:(ATProtoHttpServer *)server {
    __weak typeof(self) weakSelf = self;

    [server addRoute:@"GET" path:@"/favicon.ico"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 response.statusCode = 204;
                 [response setHeader:@"0" forKey:@"Content-Length"];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 [weakSelf writeDemoHTML:response];
             }];
    [server addRoute:@"GET" path:@"/demo/streamplace/"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 [weakSelf writeDemoHTML:response];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/overwatch"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 [weakSelf writeOverwatchHTML:response];
             }];
    [server addRoute:@"GET" path:@"/demo/streamplace/overwatch/"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 [weakSelf writeOverwatchHTML:response];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/api/overwatch"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 [weakSelf writeJSON:[weakSelf overwatchSnapshotDictionary]
                              status:200
                            response:response];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/hls.min.js"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 NSString *path = [weakSelf resolveAssetPath:@"hls.min.js"];
                 if (path.length == 0) {
                     response.statusCode = 404;
                     return;
                 }
                 response.statusCode = 200;
                 response.contentType = @"application/javascript; charset=utf-8";
                 [response setHeader:@"public, max-age=86400" forKey:@"Cache-Control"];
                 [response setBodyFileAtPath:path deleteAfterSend:NO];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/api/catalog"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 NSError *err = nil;
                 NSArray *live = [weakSelf fetchLiveStreams:&err];
                 NSArray *vod = [weakSelf fetchSampleVODs:&err];
                 [weakSelf writeJSON:@{
                     @"live": live,
                     @"vod": vod,
                     @"stats": [weakSelf allowlistedStatsDictionary],
                     @"peership": @{
                         @"model": @"VOD: getVideoBlob→CA/range-proxy; Live: getLiveSegment proxy via jelcz",
                         @"browserOrigin": weakSelf.publicBaseURL,
                         @"upstreamDiscoveryOnly": weakSelf.upstreamBaseURL,
                     },
                 } status:200 response:response];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/api/stats"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 [weakSelf writeJSON:[weakSelf allowlistedStatsDictionary] status:200 response:response];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/api/mesh"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 NSMutableDictionary *payload =
                     [[weakSelf meshStatusDictionary] mutableCopy] ?: [NSMutableDictionary dictionary];
                 payload[@"stats"] = [weakSelf allowlistedStatsDictionary];
                 [weakSelf writeJSON:payload status:200 response:response];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/api/providers"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 (void)request;
                 NSMutableArray *origins = [NSMutableArray array];
                 for (GZJelczPeerProviderEntry *e in weakSelf.originEntries) {
                     [origins addObject:[e allowlistedDictionary]];
                 }
                 [weakSelf writeJSON:@{
                     @"httpsProviders": [weakSelf effectiveHTTPSProviderBases],
                     @"envPeers": weakSelf.peerHTTPSProviders ?: @[],
                     @"origins": origins,
                     @"consent": @{
                         @"allowedStreamers": weakSelf.allowedStreamers.allObjects ?: @[],
                         @"allowedBroadcasters": weakSelf.allowedBroadcasters.allObjects ?: @[],
                     },
                 } status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/origins"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 id json = [weakSelf boundedMutationJSONForRequest:request response:response];
                 if (!json) {
                     return;
                 }
                 NSArray *parsed =
                     [GZJelczPeerProviderIndex entriesFromOriginsJSONObject:json
                                                        configuredBaseURL:weakSelf.upstreamBaseURL];
                 BOOL replaceExisting = NO;
                 if ([json isKindOfClass:[NSDictionary class]]) {
                     id replace = ((NSDictionary *)json)[@"replace"];
                     replaceExisting = [replace isKindOfClass:[NSNumber class]] && [replace boolValue];
                 }
                 NSMutableArray *merged = replaceExisting
                     ? [NSMutableArray array]
                     : [NSMutableArray arrayWithArray:weakSelf.originEntries ?: @[]];
                 [merged addObjectsFromArray:parsed];
                 weakSelf.originEntries = [merged copy];
                 [weakSelf writeJSON:@{
                     @"ingested": @(parsed.count),
                     @"replaced": @(replaceExisting),
                     @"originEntryCount": @(weakSelf.originEntries.count),
                     @"httpsProviders": [weakSelf effectiveHTTPSProviderBases],
                 } status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/seed"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 if (request.body.length == 0) {
                     [weakSelf writeJSON:@{@"error": @"InvalidRequest", @"message": @"empty body"}
                                  status:400
                                response:response];
                     return;
                 }
                 if (request.body.length > weakSelf.seedPayloadMaxBytes ||
                     request.body.length > weakSelf.fullPeerMaxBytes) {
                     [weakSelf writeJSON:@{
                         @"error": @"PayloadTooLarge",
                         @"message": @"seed body exceeds demo limit"
                     } status:413 response:response];
                     return;
                 }
                 NSError *err = nil;
                 ATProtoCID *cid = [weakSelf.objectStore putData:request.body
                                                     expectedCID:nil
                                                         profile:ATProtoCAObjectDigestProfileBLAKE3
                                                           error:&err];
                 if (!cid) {
                     [weakSelf writeJSON:@{
                         @"error": @"SeedFailed",
                         @"message": err.localizedDescription ?: @"put failed"
                     } status:500 response:response];
                     return;
                 }
                 weakSelf.peeredObjectCount += 1;
                 NSString *cidStr = cid.stringValue ?: @"";
                 NSDictionary *irohOffer =
                     [weakSelf offerBytesToIrohSidecar:request.body error:nil];
                 [weakSelf recordServeMode:@"ca-seed" bytes:request.body.length cid:cidStr note:@"demo seed"];
                 if (irohOffer) {
                     [weakSelf recordServeMode:@"iroh-offer"
                                        bytes:request.body.length
                                          cid:cidStr
                                         note:irohOffer[@"endpointId"] ?: @"sidecar"];
                 }
                 NSMutableDictionary *resp = [@{
                     @"cid": cidStr,
                     @"size": @(request.body.length),
                     @"getVideoBlobURL":
                         [NSString stringWithFormat:
                          @"%@/xrpc/place.stream.playback.getVideoBlob?did=%@&cid=%@",
                          weakSelf.publicBaseURL,
                          [weakSelf percentEncodeQueryValue:@"did:web:jelcz.local"],
                          [weakSelf percentEncodeQueryValue:cidStr]],
                     @"peerSource": @"ca-store",
                 } mutableCopy];
                 if (irohOffer) {
                     resp[@"irohOffered"] = @YES;
                     resp[@"irohEndpointId"] = irohOffer[@"endpointId"] ?: @"";
                     resp[@"irohProvider"] =
                         [NSString stringWithFormat:@"iroh://%@", irohOffer[@"endpointId"] ?: @""];
                 } else if (weakSelf.irohSidecarURL.length > 0) {
                     resp[@"irohOffered"] = @NO;
                 }
                 if (GZJelczDemoSeedFanoutEnabled(request)) {
                     NSString *irohHint = resp[@"irohProvider"];
                     NSArray *fanout = [weakSelf fanOutCIDToMesh:cidStr
                                                    irohProvider:irohHint
                                                   httpsProvider:[weakSelf localMeshJelczBase]];
                     if (fanout.count > 0) {
                         resp[@"meshFanout"] = fanout;
                     }
                 } else {
                     // Demo-only control: keeps a destination empty for a
                     // deterministic per-transport smoke assertion.
                     resp[@"meshFanoutSuppressed"] = @YES;
                 }
                 [weakSelf writeJSON:resp status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/pull-peer"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 NSDictionary *body = [weakSelf boundedMutationJSONDictionaryForRequest:request response:response];
                 if (!body) {
                     return;
                 }
                 NSString *cidStr = [body[@"cid"] isKindOfClass:[NSString class]] ? body[@"cid"] : nil;
                 NSString *provider = [body[@"provider"] isKindOfClass:[NSString class]] ? body[@"provider"] : nil;
                 NSString *did = [body[@"did"] isKindOfClass:[NSString class]] ? body[@"did"] : @"did:web:jelcz.local";
                 if (cidStr.length == 0 || provider.length == 0) {
                     [weakSelf writeJSON:@{
                         @"error": @"InvalidRequest",
                         @"message": @"cid and provider required"
                     } status:400 response:response];
                     return;
                 }
                 NSDictionary *result = [weakSelf pullPeerCID:cidStr
                                                     provider:provider
                                                          did:did
                                                        error:nil];
                 if (!result[@"cid"]) {
                     NSInteger status = [result[@"error"] isEqualToString:@"ProviderNotAllowed"] ? 403 :
                         ([result[@"error"] isEqualToString:@"InvalidRequest"] ? 400 : 502);
                     [weakSelf writeJSON:result ?: @{@"error": @"PullFailed"} status:status response:response];
                     return;
                 }
                 [weakSelf writeJSON:result status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/pull-streamplace-iroh"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 NSDictionary *body = [weakSelf boundedMutationJSONDictionaryForRequest:request response:response];
                 if (!body) {
                     return;
                 }
                 NSString *streamer = [body[@"streamer"] isKindOfClass:[NSString class]] ? body[@"streamer"] : nil;
                 if (streamer.length == 0) {
                     [weakSelf writeJSON:@{ @"error": @"InvalidRequest", @"message": @"streamer required" }
                                  status:400
                                response:response];
                     return;
                 }
                 GZJelczStreamplaceIrohBridge *bridge = weakSelf.streamplaceIrohBridge;
                 if (!bridge) {
                     [weakSelf writeJSON:@{ @"error": @"BridgeDisabled", @"message": @"Streamplace live bridge is not configured" }
                                  status:503
                                response:response];
                     return;
                 }
                 GZJelczPeerProviderEntry *origin = nil;
                 for (GZJelczPeerProviderEntry *entry in
                      [GZJelczPeerProviderIndex rankEntries:weakSelf.originEntries ?: @[]]) {
                     if ([entry.streamerDID isEqualToString:streamer]) {
                         origin = entry;
                         break;
                     }
                 }
                 if (!origin) {
                     [weakSelf writeJSON:@{ @"error": @"OriginNotFound", @"message": @"No broadcast origin for streamer" }
                                  status:404
                                response:response];
                     return;
                 }
                 NSError *error = nil;
                 GZJelczStreamplaceIrohBridgeEvidence *evidence = nil;
                 NSData *segment = [bridge receiveSegmentFromOrigin:origin
                                                                  now:[NSDate date]
                                                             evidence:&evidence
                                                                error:&error];
                 if (!segment) {
                     GZJelczStreamplaceIrohBridgeErrorCode code =
                         (GZJelczStreamplaceIrohBridgeErrorCode)error.code;
                     NSInteger status = (code == GZJelczStreamplaceIrohBridgeErrorDenied) ? 403 :
                         ((code == GZJelczStreamplaceIrohBridgeErrorStaleOrigin) ? 422 :
                          ((code == GZJelczStreamplaceIrohBridgeErrorInvalidOrigin) ? 400 :
                           ((code == GZJelczStreamplaceIrohBridgeErrorBodyTooLarge) ? 413 :
                            ((code == GZJelczStreamplaceIrohBridgeErrorInvalidMUXL) ? 422 :
                             ((code == GZJelczStreamplaceIrohBridgeErrorAttestationRejected) ? 409 : 502)))));
                     NSString *kind = (code == GZJelczStreamplaceIrohBridgeErrorDenied) ? @"StreamerNotAllowed" :
                         ((code == GZJelczStreamplaceIrohBridgeErrorStaleOrigin) ? @"OriginStale" :
                          ((code == GZJelczStreamplaceIrohBridgeErrorInvalidOrigin) ? @"OriginInvalid" :
                           ((code == GZJelczStreamplaceIrohBridgeErrorBodyTooLarge) ? @"BridgeResponseTooLarge" :
                            ((code == GZJelczStreamplaceIrohBridgeErrorInvalidMUXL) ? @"MUXLInvalid" :
                             ((code == GZJelczStreamplaceIrohBridgeErrorMissingSession) ? @"BridgeSessionMissing" :
                              ((code == GZJelczStreamplaceIrohBridgeErrorAttestationRejected) ?
                               @"EvidenceAttestationRejected" : @"BridgeSubscriptionFailed"))))));
                     [weakSelf writeJSON:@{ @"error": kind,
                                             @"message": error.localizedDescription ?: @"Bridge subscription failed" }
                                  status:status
                                response:response];
                     return;
                 }
                 // Evidence only: the Track B segment remains in-memory and caller-owned.
                 [weakSelf writeJSON:@{ @"streamer": streamer,
                                         @"sessionId": evidence.sessionID ?: @"",
                                         @"bytes": @(evidence.contentBytes),
                                         @"ticketFingerprint": evidence.ticketFingerprint ?: @"",
                                         @"contentSha256": evidence.contentSHA256 ?: @"",
                                         @"digest": evidence.contentSHA256 ?: @"",
                                         @"validation": @(evidence.isStructurallyValid) }
                              status:200
                            response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/mesh-replicate"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 NSDictionary *body = [weakSelf boundedMutationJSONDictionaryForRequest:request response:response];
                 if (!body) {
                     return;
                 }
                 NSString *cidStr = [body[@"cid"] isKindOfClass:[NSString class]] ? body[@"cid"] : nil;
                 if (cidStr.length == 0) {
                     [weakSelf writeJSON:@{
                         @"error": @"InvalidRequest",
                         @"message": @"cid required"
                     } status:400 response:response];
                     return;
                 }
                 NSString *irohHint = [body[@"irohProvider"] isKindOfClass:[NSString class]] ? body[@"irohProvider"] : nil;
                 if (irohHint.length == 0 && weakSelf.irohPeerRegistry.localIdentity.endpointId.length > 0) {
                     irohHint = [NSString stringWithFormat:@"iroh://%@",
                                 weakSelf.irohPeerRegistry.localIdentity.endpointId];
                 }
                 NSArray *fanout = [weakSelf fanOutCIDToMesh:cidStr
                                                irohProvider:irohHint
                                               httpsProvider:[weakSelf localMeshJelczBase]];
                 [weakSelf writeJSON:@{
                     @"cid": cidStr,
                     @"from": weakSelf.nodeName ?: @"jelcz",
                     @"meshFanout": fanout,
                 } status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/announce-origin"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 if (!weakSelf.originAnnouncer) {
                     [weakSelf writeJSON:@{
                         @"error": @"AnnounceDisabled",
                         @"message": @"set JELCZ_ORIGIN_ANNOUNCE=1 and PDS credentials"
                     } status:503 response:response];
                     return;
                 }
                 NSDictionary *body = [weakSelf boundedMutationJSONDictionaryForRequest:request response:response];
                 if (!body) {
                     return;
                 }
                 NSString *subjectURI = [body[@"subjectUri"] isKindOfClass:[NSString class]] ? body[@"subjectUri"] :
                     ([body[@"uri"] isKindOfClass:[NSString class]] ? body[@"uri"] : nil);
                 NSString *subjectCID = [body[@"subjectCid"] isKindOfClass:[NSString class]] ? body[@"subjectCid"] :
                     ([body[@"cid"] isKindOfClass:[NSString class]] ? body[@"cid"] : @"");
                 NSString *manifestCID = [body[@"manifestCid"] isKindOfClass:[NSString class]] ? body[@"manifestCid"] : subjectCID;
                 NSString *watchBase = [body[@"watchBaseUrl"] isKindOfClass:[NSString class]] ? body[@"watchBaseUrl"] : weakSelf.publicBaseURL;
                 NSString *httpsBase = [body[@"httpsBase"] isKindOfClass:[NSString class]] ? body[@"httpsBase"] : weakSelf.originAnnouncer.httpsBase;
                 NSString *irohEndpointId = [body[@"irohEndpointId"] isKindOfClass:[NSString class]] ? body[@"irohEndpointId"] : weakSelf.originAnnouncer.irohEndpointId;
                 NSString *irohEndpointTicket = [body[@"irohEndpointTicket"] isKindOfClass:[NSString class]] ? body[@"irohEndpointTicket"] : weakSelf.originAnnouncer.irohEndpointTicket;
                 NSString *rkey = [body[@"rkey"] isKindOfClass:[NSString class]] ? body[@"rkey"] : nil;
                 if (subjectURI.length == 0 || manifestCID.length == 0) {
                     [weakSelf writeJSON:@{
                         @"error": @"InvalidRequest",
                         @"message": @"subjectUri and manifestCid (or cid) required"
                     } status:400 response:response];
                     return;
                 }
                 NSDictionary *record =
                     [GZJelczOriginAnnouncer originRecordWithSubjectURI:subjectURI
                                                             subjectCID:subjectCID
                                                              serverDID:weakSelf.originAnnouncer.serverDID
                                                           watchBaseURL:watchBase
                                                            manifestCID:manifestCID
                                                              httpsBase:httpsBase
                                                         irohEndpointId:irohEndpointId
                                                     irohEndpointTicket:irohEndpointTicket
                                                                    now:[NSDate date]];
                 NSError *err = nil;
                 NSDictionary *published = [weakSelf.originAnnouncer publishOriginRecord:record
                                                                                    rkey:rkey
                                                                                   error:&err];
                 if (!published) {
                     [weakSelf writeJSON:@{
                         @"error": @"AnnounceFailed",
                         @"message": err.localizedDescription ?: @"putRecord failed"
                     } status:502 response:response];
                     return;
                 }
                 [weakSelf writeJSON:published status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/retract-origin"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 if (!weakSelf.originAnnouncer) {
                     [weakSelf writeJSON:@{
                         @"error": @"AnnounceDisabled",
                         @"message": @"set JELCZ_ORIGIN_ANNOUNCE=1 and PDS credentials"
                     } status:503 response:response];
                     return;
                 }
                 NSDictionary *body = [weakSelf boundedMutationJSONDictionaryForRequest:request response:response];
                 if (!body) {
                     return;
                 }
                 NSString *rkey = [body[@"rkey"] isKindOfClass:[NSString class]] ? body[@"rkey"] : nil;
                 if (rkey.length == 0) {
                     [weakSelf writeJSON:@{
                         @"error": @"InvalidRequest",
                         @"message": @"rkey required"
                     } status:400 response:response];
                     return;
                 }
                 NSError *err = nil;
                 if (![weakSelf.originAnnouncer retractOriginWithRkey:rkey error:&err]) {
                     [weakSelf writeJSON:@{
                         @"error": @"RetractFailed",
                         @"message": err.localizedDescription ?: @"deleteRecord failed"
                     } status:502 response:response];
                     return;
                 }
                 [weakSelf writeJSON:@{@"retracted": @YES, @"rkey": rkey} status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/peer"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (![weakSelf authorizeMutationRequest:request response:response]) {
                     return;
                 }
                 NSDictionary *body = [weakSelf boundedMutationJSONDictionaryForRequest:request response:response];
                 if (!body) {
                     return;
                 }
                 NSString *kind = [body[@"kind"] isKindOfClass:[NSString class]] ? body[@"kind"] : nil;
                 if (kind.length == 0) {
                     kind = [request queryParamForKey:@"kind"];
                 }
                 NSError *err = nil;
                 NSDictionary *session = nil;
                 NSString *bodyDID = [body[@"did"] isKindOfClass:[NSString class]] ? body[@"did"] : nil;
                 NSString *bodyURI = [body[@"uri"] isKindOfClass:[NSString class]] ? body[@"uri"] : nil;
                 if ([kind isEqualToString:@"live"] || (bodyDID && !bodyURI)) {
                     NSString *did = bodyDID ?: ([body[@"streamer"] isKindOfClass:[NSString class]] ? body[@"streamer"] : nil) ?: [request queryParamForKey:@"did"];
                     session = [weakSelf peerLiveStreamer:did error:&err];
                 } else {
                     NSString *uri = bodyURI;
                     if (uri.length == 0) {
                         uri = [request queryParamForKey:@"uri"];
                     }
                     session = [weakSelf peerVODURI:uri error:&err];
                 }
                 if (!session) {
                     [weakSelf writeJSON:@{
                         @"error": @"PeerFailed",
                         @"message": err.localizedDescription ?: @"peer failed"
                     } status:502 response:response];
                     return;
                 }
                 [weakSelf writeJSON:session status:200 response:response];
             }];

    [server addRoute:@"GET" path:@"/demo/streamplace/playlist"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 NSString *uri = [request queryParamForKey:@"uri"];
                 NSString *track = [request queryParamForKey:@"track"];
                 NSString *sid = [request queryParamForKey:@"sid"];
                 NSString *start = [request queryParamForKey:@"start"];
                 NSString *end = [request queryParamForKey:@"end"];
                 NSMutableString *q = [NSMutableString string];
                 void (^add)(NSString *, NSString *) = ^(NSString *k, NSString *v) {
                     if (v.length == 0) return;
                     if (q.length > 0) [q appendString:@"&"];
                     [q appendFormat:@"%@=%@", k, [weakSelf percentEncodeQueryValue:v]];
                 };
                 add(@"uri", uri);
                 add(@"track", track);
                 add(@"sid", sid);
                 add(@"start", start);
                 add(@"end", end);
                 NSString *path = [NSString stringWithFormat:
                                   @"/xrpc/place.stream.playback.getVideoPlaylist?%@", q];
                 NSError *err = nil;
                 NSHTTPURLResponse *up = nil;
                 NSData *data = [weakSelf vodGET:path rangeHeader:nil response:&up error:&err];
                 if (!data || up.statusCode != 200) {
                     [weakSelf writeJSON:@{
                         @"error": @"PlaylistFailed",
                         @"message": err.localizedDescription ?: @"upstream playlist failed"
                     } status:502 response:response];
                     return;
                 }
                 NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                 NSString *rewritten = [weakSelf rewritePlaylist:text];
                 response.statusCode = 200;
                 response.contentType = @"application/vnd.apple.mpegurl";
                 [response setHeader:@"jelcz-rewritten" forKey:@"X-Jelcz-Peer"];
                 [weakSelf recordServeMode:@"playlist-rewrite"
                                    bytes:rewritten.length
                                      cid:nil
                                     note:@"VOD playlist → jelcz URLs"];
                 [response setBodyString:rewritten];
             }];

    void (^forwardLiveQuery)(ATProtoHttpRequest *, NSString *, ATProtoHttpResponse *) =
        ^(ATProtoHttpRequest *request, NSString *xrpcMethod, ATProtoHttpResponse *response) {
            NSArray *keys = @[ @"streamer", @"sid", @"track", @"seg", @"rendition" ];
            NSMutableString *q = [NSMutableString string];
            for (NSString *k in keys) {
                NSString *v = [request queryParamForKey:k];
                if (v.length == 0) continue;
                if (q.length > 0) [q appendString:@"&"];
                [q appendFormat:@"%@=%@", k, [weakSelf percentEncodeQueryValue:v]];
            }
            // Also forward any leftover raw query if needed.
            NSString *path = q.length > 0
                ? [NSString stringWithFormat:@"/xrpc/%@?%@", xrpcMethod, q]
                : [NSString stringWithFormat:@"/xrpc/%@", xrpcMethod];
            NSError *err = nil;
            if ([xrpcMethod containsString:@"Playlist"]) {
                NSHTTPURLResponse *up = nil;
                NSData *data = [weakSelf upstreamGET:path rangeHeader:nil response:&up error:&err];
                if (!data || up.statusCode != 200) {
                    [weakSelf writeJSON:@{
                        @"error": @"LivePlaylistFailed",
                        @"message": err.localizedDescription ?: @"upstream live playlist failed"
                    } status:502 response:response];
                    return;
                }
                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                response.statusCode = 200;
                response.contentType = @"application/vnd.apple.mpegurl";
                [response setHeader:@"jelcz-live-rewritten" forKey:@"X-Jelcz-Peer"];
                NSString *rewritten = [weakSelf rewriteLivePlaylist:text];
                [weakSelf recordServeMode:@"playlist-rewrite"
                                   bytes:rewritten.length
                                     cid:nil
                                    note:@"live playlist → jelcz URLs"];
                [response setBodyString:rewritten];
                return;
            }
            NSString *range = [request headerForKey:@"Range"];
            if (![weakSelf proxyUpstreamPath:path rangeHeader:range response:response error:&err]) {
                if (response.statusCode < 400) {
                    response.statusCode = 502;
                }
            }
        };

    [server addRoute:@"GET" path:@"/demo/streamplace/live/playlist"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 forwardLiveQuery(request, @"place.stream.playback.getLivePlaylist", response);
             }];
    [server addRoute:@"GET" path:@"/demo/streamplace/live/segment"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 forwardLiveQuery(request, @"place.stream.playback.getLiveSegment", response);
             }];

    GZ_LOG_INFO(@"Streamplace peer demo routes on /demo/streamplace (UI + overwatch + VOD + live proxy)");
}

@end

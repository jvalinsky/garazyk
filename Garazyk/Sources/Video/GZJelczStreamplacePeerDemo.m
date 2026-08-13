// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczStreamplacePeerDemo.h"
#import "Video/GZJelczStreamplaceBlobFetcher.h"
#import "Video/GZJelczStreamplaceCompatServe.h"
#import "Video/GZJelczStreamplaceOriginHints.h"
#import "Video/GZJelczPeerProviderIndex.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

static NSString * const kDemoHTMLResourceRelative =
    @"Garazyk/Resources/jelcz-demo/streamplace-peer.html";

@interface GZJelczDemoURLSessionHTTPClient : NSObject <ATProtoCAMirrorHTTPClient>
@end

@implementation GZJelczDemoURLSessionHTTPClient
- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    (void)options;
    __block NSData *body = nil;
    __block NSHTTPURLResponse *resp = nil;
    __block NSError *reqError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = MAX(request.timeoutInterval, 30.0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithRequest:request
                completionHandler:^(NSData *data, NSURLResponse *urlResp, NSError *taskError) {
                    body = data;
                    resp = (NSHTTPURLResponse *)urlResp;
                    reqError = taskError;
                    dispatch_semaphore_signal(sema);
                    [session finishTasksAndInvalidate];
                }] resume];
    NSTimeInterval wait = cfg.timeoutIntervalForRequest + 5.0;
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

@interface GZJelczStreamplacePeerDemo ()
@property (atomic, assign, readwrite) NSUInteger peeredObjectCount;
@property (atomic, assign, readwrite) NSUInteger proxiedByteCount;
@property (atomic, assign, readwrite) NSUInteger localServeCount;
@property (atomic, assign, readwrite) NSUInteger proxyServeCount;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *peerSessions;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *recentServes;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) id<ATProtoCAMirrorHTTPClient> sessionHTTPClient;
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
        _peerSessions = [NSMutableDictionary dictionary];
        _recentServes = [NSMutableArray array];
        _lock = [[NSLock alloc] init];
        _peerHTTPSProviders = @[];
        _originEntries = @[];
        _allowedStreamers = [NSSet set];
        _allowedBroadcasters = [NSSet set];
    }
    return self;
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
    NSString *base = [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:provider];
    if (base.length == 0 || cidStr.length == 0) {
        return @{@"error": @"InvalidRequest", @"message": @"bad provider or cid"};
    }
    ATProtoCID *cid = [ATProtoCID daslCIDFromString:cidStr profile:ATProtoDASLCIDProfileBig];
    if (!cid) {
        return @{@"error": @"InvalidRequest", @"message": @"Invalid cid"};
    }
    NSDictionary *local = [self.objectStore statCID:cid error:nil];
    if (local) {
        return @{
            @"cid": cidStr,
            @"status": @"already-local",
            @"size": local[@"size"] ?: @0,
            @"peerSource": @"ca-store",
            @"provider": base,
        };
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
    self.peeredObjectCount += 1;
    [self recordServeMode:@"https-peer" bytes:bytes.length cid:cidStr note:base];
    return @{
        @"cid": cidStr,
        @"status": @"peered-verified",
        @"size": @(bytes.length),
        @"peerSource": @"https-peer",
        @"provider": base,
        @"blake3Verified": @YES,
    };
}

- (void)recordServeMode:(NSString *)mode
                  bytes:(NSUInteger)bytes
                    cid:(NSString *)cid
                   note:(NSString *)note {
    if (mode.length == 0) return;
    NSMutableDictionary *entry = [@{
        @"ts": @([[NSDate date] timeIntervalSince1970]),
        @"mode": mode,
        @"bytes": @(bytes),
        @"via": @"jelcz",
    } mutableCopy];
    if (cid.length > 0) entry[@"cid"] = cid;
    if (note.length > 0) entry[@"note"] = note;
    [self.lock lock];
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
    response.contentType = @"application/json; charset=utf-8";
    [response setHeader:@"no-store" forKey:@"Cache-Control"];
    [response setJsonBody:obj];
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
    NSData *body = [self upstreamGET:path rangeHeader:@"bytes=0-0" response:&resp error:error];
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
    NSData *masterData = [self upstreamGET:playlistPath rangeHeader:nil response:&masterResp error:error];
    if (!masterData || masterResp.statusCode != 200) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"GZJelczStreamplacePeerDemo"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch master playlist"}];
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
    NSData *mediaData = [self upstreamGET:mediaPath rangeHeader:nil response:&mediaResp error:error];
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
            continue;
        }
        if (size > 0 && size <= self.fullPeerMaxBytes) {
            NSError *fetchErr = nil;
            NSData *bytes = [resolver dataForCID:cid
                                       providers:@[ self.upstreamBaseURL ]
                                           error:&fetchErr];
            if (bytes) {
                self.peeredObjectCount += 1;
                [objects addObject:@{
                    @"cid": cidStr,
                    @"status": @"peered-verified",
                    @"size": @(bytes.length),
                    @"mode": @"ca-store",
                    @"blake3Verified": @YES,
                }];
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

- (NSString *)loadHTML {
    NSArray *candidates = @[
        [[[NSProcessInfo processInfo] environment] objectForKey:@"JELCZ_DEMO_UI_PATH"] ?: @"",
        kDemoHTMLResourceRelative,
        [@"../" stringByAppendingString:kDemoHTMLResourceRelative],
    ];
    for (NSString *path in candidates) {
        if (path.length == 0) continue;
        NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (html.length > 0) return html;
    }
    return @"<!doctype html><meta charset=utf-8><title>jelcz peer demo</title>"
           @"<p>Missing Garazyk/Resources/jelcz-demo/streamplace-peer.html — set JELCZ_DEMO_UI_PATH.</p>";
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
                 id json = nil;
                 if (request.body.length > 0) {
                     json = [NSJSONSerialization JSONObjectWithData:request.body options:0 error:nil];
                 }
                 NSArray *parsed =
                     [GZJelczPeerProviderIndex entriesFromOriginsJSONObject:json
                                                        configuredBaseURL:weakSelf.upstreamBaseURL];
                 NSMutableArray *merged = [NSMutableArray arrayWithArray:weakSelf.originEntries ?: @[]];
                 [merged addObjectsFromArray:parsed];
                 weakSelf.originEntries = [merged copy];
                 [weakSelf writeJSON:@{
                     @"ingested": @(parsed.count),
                     @"originEntryCount": @(weakSelf.originEntries.count),
                     @"httpsProviders": [weakSelf effectiveHTTPSProviderBases],
                 } status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/seed"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 if (request.body.length == 0) {
                     [weakSelf writeJSON:@{@"error": @"InvalidRequest", @"message": @"empty body"}
                                  status:400
                                response:response];
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
                 [weakSelf recordServeMode:@"ca-seed" bytes:request.body.length cid:cidStr note:@"demo seed"];
                 [weakSelf writeJSON:@{
                     @"cid": cidStr,
                     @"size": @(request.body.length),
                     @"getVideoBlobURL":
                         [NSString stringWithFormat:
                          @"%@/xrpc/place.stream.playback.getVideoBlob?did=%@&cid=%@",
                          weakSelf.publicBaseURL,
                          [weakSelf percentEncodeQueryValue:@"did:web:jelcz.local"],
                          [weakSelf percentEncodeQueryValue:cidStr]],
                     @"peerSource": @"ca-store",
                 } status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/pull-peer"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 NSDictionary *body = nil;
                 if (request.body.length > 0) {
                     body = [NSJSONSerialization JSONObjectWithData:request.body options:0 error:nil];
                 }
                 NSString *cidStr = body[@"cid"];
                 NSString *provider = body[@"provider"];
                 NSString *did = body[@"did"] ?: @"did:web:jelcz.local";
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
                     [weakSelf writeJSON:result ?: @{@"error": @"PullFailed"} status:502 response:response];
                     return;
                 }
                 [weakSelf writeJSON:result status:200 response:response];
             }];

    [server addRoute:@"POST" path:@"/demo/streamplace/api/peer"
             handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                 NSDictionary *body = nil;
                 if (request.body.length > 0) {
                     body = [NSJSONSerialization JSONObjectWithData:request.body options:0 error:nil];
                 }
                 NSString *kind = body[@"kind"];
                 if (kind.length == 0) {
                     kind = [request queryParamForKey:@"kind"];
                 }
                 NSError *err = nil;
                 NSDictionary *session = nil;
                 if ([kind isEqualToString:@"live"] || (body[@"did"] && !body[@"uri"])) {
                     NSString *did = body[@"did"] ?: body[@"streamer"] ?: [request queryParamForKey:@"did"];
                     session = [weakSelf peerLiveStreamer:did error:&err];
                 } else {
                     NSString *uri = body[@"uri"];
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
                 NSData *data = [weakSelf upstreamGET:path rangeHeader:nil response:&up error:&err];
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

    GZ_LOG_INFO(@"Streamplace peer demo routes on /demo/streamplace (UI + VOD + live proxy)");
}

@end

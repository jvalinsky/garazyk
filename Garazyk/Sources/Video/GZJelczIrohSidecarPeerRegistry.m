// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczIrohSidecarPeerRegistry.h"
#import "Video/GZJelczIrohSidecarURL.h"

@implementation GZJelczIrohSidecarPeerIdentity
@end

@implementation GZJelczIrohSidecarPeerRegistry

+ (nullable NSDictionary *)identityJSONFromSidecar:(NSString *)baseURL
                                        trustLan:(BOOL)trustLan
                               capabilityToken:(NSString *)capabilityToken
                                      httpClient:(id<ATProtoCAMirrorHTTPClient>)httpClient {
    NSString *normalized = [GZJelczIrohSidecarURL normalizedHTTPBase:baseURL trustLan:trustLan];
    if (normalized.length == 0) {
        return nil;
    }
    NSURL *url = [NSURL URLWithString:[normalized stringByAppendingString:@"/v1/identity"]];
    if (!url) {
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    if (capabilityToken.length > 0) {
        [req setValue:[@"Bearer " stringByAppendingString:capabilityToken]
forHTTPHeaderField:@"Authorization"];
    }
    NSHTTPURLResponse *resp = nil;
    NSError *error = nil;
    NSData *body = [httpClient sendSynchronousRequest:req options:nil response:&resp error:&error];
    if (!body || resp.statusCode != 200) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

+ (instancetype)registryWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                       localSidecarURL:(NSString *)localSidecarURL
                              peerSidecarURLs:(NSArray<NSString *> *)peerSidecarURLs
                                     nodeName:(NSString *)nodeName
                              trustLan:(BOOL)trustLan
                       capabilityToken:(NSString *)capabilityToken {
    NSParameterAssert(httpClient);
    GZJelczIrohSidecarPeerRegistry *reg = [[self alloc] initPrivate];
    reg->_nodeName = [nodeName copy] ?: @"jelcz";
    NSMutableArray<GZJelczIrohSidecarPeerIdentity *> *remotes = [NSMutableArray array];
    if (capabilityToken.length == 0) {
        reg->_remoteIdentities = @[];
        return reg;
    }

    if (localSidecarURL.length > 0) {
        NSString *localBase = [GZJelczIrohSidecarURL normalizedHTTPBase:localSidecarURL trustLan:trustLan];
        NSDictionary *json = [self identityJSONFromSidecar:localBase
                                                   trustLan:trustLan
                                            capabilityToken:capabilityToken
                                                 httpClient:httpClient];
        if (json[@"endpointId"]) {
            GZJelczIrohSidecarPeerIdentity *local = [[GZJelczIrohSidecarPeerIdentity alloc] init];
            local.nodeName = reg.nodeName;
            local.sidecarURL = localBase;
            local.endpointId = json[@"endpointId"];
            local.endpointTicket = json[@"endpointTicket"] ?: @"";
            local.local = YES;
            reg->_localIdentity = local;
        }
    }

    for (NSString *peerURL in peerSidecarURLs) {
        if (peerURL.length == 0) {
            continue;
        }
        NSString *peerBase = [GZJelczIrohSidecarURL normalizedHTTPBase:peerURL trustLan:trustLan];
        if (peerBase.length == 0) {
            continue;
        }
        NSDictionary *json = [self identityJSONFromSidecar:peerBase
                                                   trustLan:trustLan
                                            capabilityToken:capabilityToken
                                                 httpClient:httpClient];
        if (!json[@"endpointId"]) {
            continue;
        }
        GZJelczIrohSidecarPeerIdentity *remote = [[GZJelczIrohSidecarPeerIdentity alloc] init];
        NSURL *u = [NSURL URLWithString:peerBase];
        remote.nodeName = u.host ?: peerBase;
        remote.sidecarURL = peerBase;
        remote.endpointId = json[@"endpointId"];
        remote.endpointTicket = json[@"endpointTicket"] ?: @"";
        remote.local = NO;
        [remotes addObject:remote];
    }
    reg->_remoteIdentities = [remotes copy];
    return reg;
}

- (instancetype)initPrivate {
    self = [super init];
    return self;
}

- (NSArray<NSString *> *)irohProviderHints {
    NSMutableArray *hints = [NSMutableArray array];
    for (GZJelczIrohSidecarPeerIdentity *peer in self.remoteIdentities) {
        if (peer.endpointId.length > 0) {
            [hints addObject:[NSString stringWithFormat:@"iroh://%@", peer.endpointId]];
        }
    }
    return hints;
}

- (NSString *)endpointTicketForEndpointId:(NSString *)endpointId {
    if (endpointId.length == 0) {
        return nil;
    }
    if ([self.localIdentity.endpointId isEqualToString:endpointId]) {
        return self.localIdentity.endpointTicket;
    }
    for (GZJelczIrohSidecarPeerIdentity *peer in self.remoteIdentities) {
        if ([peer.endpointId isEqualToString:endpointId]) {
            return peer.endpointTicket;
        }
    }
    return nil;
}

- (NSArray<NSDictionary *> *)meshTopologyNodes:(NSArray<NSDictionary *> *)configuredNodes {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *node in configuredNodes) {
        if (![node isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = node[@"name"];
        NSString *sidecar = node[@"sidecar"];
        NSString *jelcz = node[@"jelcz"];
        NSString *kind = node[@"kind"] ?: @"jelcz";
        NSString *endpointId = nil;
        if (sidecar.length > 0) {
            for (GZJelczIrohSidecarPeerIdentity *peer in self.remoteIdentities) {
                if ([peer.sidecarURL isEqualToString:sidecar] ||
                    [peer.nodeName isEqualToString:name]) {
                    endpointId = peer.endpointId;
                    break;
                }
            }
            if ([self.localIdentity.sidecarURL isEqualToString:sidecar] ||
                [self.nodeName isEqualToString:name]) {
                endpointId = self.localIdentity.endpointId;
            }
        }
        NSMutableDictionary *entry = [@{
            @"name": name ?: @"?",
            @"kind": kind,
        } mutableCopy];
        if (jelcz.length > 0) entry[@"jelcz"] = jelcz;
        if (sidecar.length > 0) entry[@"sidecar"] = sidecar;
        if (endpointId.length > 0) entry[@"irohEndpointId"] = endpointId;
        [out addObject:entry];
    }
    return out;
}

@end

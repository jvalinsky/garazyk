// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/AdminUI/RelayAdminSnapshot.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Compat/PDSTypes.h"

NSString *GZRelayAdminPasswordFromFile(NSString *path, NSError **error) {
    NSString *password = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!password) {
        if (error) *error = [NSError errorWithDomain:@"GZRelayAdminUI" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"Unable to read relay admin password file"
        }];
        return nil;
    }
    password = [password stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if (password.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"GZRelayAdminUI" code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"Relay admin password file is empty"
        }];
        return nil;
    }
    return password;
}

@interface GZRelayAdminSnapshot ()
@property(nonatomic, strong) ATProtoRelayMetrics *metrics;
@property(nonatomic, strong) ATProtoRelayUpstreamManager *upstreamManager;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *adminAudit;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@end

@implementation GZRelayAdminSnapshot
- (instancetype)initWithMetrics:(ATProtoRelayMetrics *)metrics upstreamManager:(ATProtoRelayUpstreamManager *)upstreamManager {
    self = [super init];
    if (self) {
        _metrics = metrics;
        _upstreamManager = upstreamManager;
        _adminAudit = [NSMutableArray array];
        _queue = dispatch_queue_create("com.atproto.relay.admin.snapshot", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSDictionary<NSString *, id> *)snapshot {
    __block NSDictionary *result = nil;
    dispatch_sync(self.queue, ^{
        NSDictionary *metrics = [self.metrics snapshotDictionary] ?: @{};
        NSMutableArray *upstreams = [NSMutableArray array];
        for (NSString *url in [self.upstreamManager allUpstreams]) {
            NSURL *parsed = [NSURL URLWithString:url];
            RelayHostStatus status = [self.upstreamManager statusForUpstream:url];
            RelayCrawlState crawlState = [self.upstreamManager crawlStateForUpstream:url];
            NSString *statusName = status == RelayHostStatusActive ? @"connected" :
                (status == RelayHostStatusError ? @"failed" : @"disconnected");
            NSString *crawlStateName = crawlState == RelayCrawlStateRequested ? @"requested" :
                (crawlState == RelayCrawlStateCrawling ? @"crawling" :
                 (crawlState == RelayCrawlStateComplete ? @"complete" :
                  (crawlState == RelayCrawlStateFailed ? @"failed" : @"not requested")));
            NSDate *lastEventAt = [self.upstreamManager lastEventAtForUpstream:url];
            NSDate *connectedAt = [self.upstreamManager connectedAtForUpstream:url];
            NSDictionary *byKind = [self.upstreamManager eventCountsByKindForUpstream:url] ?: @{};
            // Bound kind map: keep at most 8 kinds sorted by count desc for the inspector.
            NSArray *kindKeys = [byKind keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
                return [b compare:a];
            }];
            if (kindKeys.count > 8) kindKeys = [kindKeys subarrayWithRange:NSMakeRange(0, 8)];
            NSMutableDictionary *boundedKinds = [NSMutableDictionary dictionary];
            for (NSString *kind in kindKeys) {
                boundedKinds[kind] = byKind[kind] ?: @0;
            }
            NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
            [upstreams addObject:@{
                @"url": url,
                @"hostname": parsed.host ?: url,
                @"connected": @([self.upstreamManager isConnectedToUpstream:url]),
                @"status": statusName,
                @"eventsReceived": @([self.upstreamManager eventCountForUpstream:url]),
                @"eventsByKind": [boundedKinds copy],
                @"lastEventAt": lastEventAt ? [iso stringFromDate:lastEventAt] : @"",
                @"connectedAt": connectedAt ? [iso stringFromDate:connectedAt] : @"",
                @"cursor": @([self.upstreamManager seqForUpstream:url]),
                @"repositories": @([self.upstreamManager crawlRepoCountForUpstream:url]),
                @"crawlState": crawlStateName,
                @"reconnectAttempts": @([self.upstreamManager reconnectAttemptsForUpstream:url]),
                @"crawlError": [self.upstreamManager crawlErrorForUpstream:url] ?: @"",
            }];
        }
        NSUInteger connected = [[upstreams filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
            return [entry[@"connected"] boolValue];
        }]] count];
        result = @{
            @"health": connected == 0 && upstreams.count > 0 ? @"degraded" : @"healthy",
            @"metrics": metrics,
            @"upstreams": upstreams,
            @"connectedUpstreams": @(connected),
            @"adminAudit": [self.adminAudit copy],
        };
    });
    return result;
}

- (NSDictionary<NSString *, id> *)performAction:(NSString *)action
                                      hostname:(NSString *)hostname {
    __block NSDictionary *result = nil;
    dispatch_sync(self.queue, ^{
        if ([action isEqualToString:@"reconnect-all"]) {
            [self.upstreamManager connectAll];
            result = @{ @"success": @YES, @"message": @"Reconnect requested for all sources." };
        } else if ([action isEqualToString:@"disconnect-all"]) {
            [self.upstreamManager disconnectAll];
            result = @{ @"success": @YES, @"message": @"All sources disconnected." };
        } else if (![action isEqualToString:@"request-crawl"] || hostname.length == 0) {
            result = @{ @"error": @"invalid_action", @"message": @"A hostname is required to request a crawl." };
        } else {
            NSString *url = [hostname hasPrefix:@"ws"] ? hostname :
                [NSString stringWithFormat:@"wss://%@/xrpc/com.atproto.sync.subscribeRepos", hostname];
            [self.upstreamManager markCrawlRequestedForUpstream:url];
            if ([[self.upstreamManager allUpstreams] containsObject:url]) {
                [self.upstreamManager connectToUpstream:url];
                result = @{ @"success": @YES, @"message": @"Reconnect requested for the source." };
            } else {
                [self.upstreamManager addUpstream:url];
                result = @{ @"success": @YES, @"message": @"Crawl requested for the source." };
            }
        }
        NSDictionary *entry = @{
            @"action": action ?: @"",
            @"hostname": hostname ?: @"",
            @"succeeded": @(!result[@"error"]),
            @"at": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
        };
        [self.adminAudit addObject:entry];
        if (self.adminAudit.count > 64) [self.adminAudit removeObjectAtIndex:0];
    });
    return result;
}
@end

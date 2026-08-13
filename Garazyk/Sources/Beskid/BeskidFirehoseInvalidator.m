// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Beskid/BeskidFirehoseInvalidator.h"
#import "Beskid/BeskidConfiguration.h"
#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidMetrics.h"
#import "Sync/Firehose/Firehose.h"
#import "Debug/GZLogger.h"

static int64_t GZBeskidReadCursorFromFile(NSString *path) {
    if (path.length == 0) return 0;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) return 0;
    return (int64_t)[text longLongValue];
}

static void GZBeskidWriteCursorToFile(NSString *path, int64_t cursor) {
    if (path.length == 0 || cursor <= 0) return;
    NSString *directory = [path stringByDeletingLastPathComponent];
    if (directory.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    [[NSString stringWithFormat:@"%lld", (long long)cursor] writeToFile:path
                                                              atomically:YES
                                                                encoding:NSUTF8StringEncoding
                                                                   error:nil];
}

@interface GZBeskidFirehoseInvalidator () <FirehoseSubscriptionDelegate> {
    BOOL _shouldReconnect;
    NSInteger _reconnectAttempts;
}

@property (nonatomic, strong) GZBeskidDatabase *database;
@property (nonatomic, strong) GZBeskidMetrics *metrics;
@property (nonatomic, strong) GZBeskidConfiguration *configuration;
@property (nonatomic, strong, nullable) ATProtoFirehose *firehose;
@property (nonatomic, strong, nullable) ATProtoFirehoseSubscription *subscription;
@property (nonatomic, copy) NSString *cursorPath;
@property (nonatomic, assign, readwrite) int64_t currentCursor;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, assign, readwrite, getter=isConnected) BOOL connected;

@end

@implementation GZBeskidFirehoseInvalidator

- (instancetype)initWithDatabase:(GZBeskidDatabase *)database
                         metrics:(GZBeskidMetrics *)metrics
                   configuration:(GZBeskidConfiguration *)configuration {
    self = [super init];
    if (self) {
        _database = database;
        _metrics = metrics;
        _configuration = configuration;
    }
    return self;
}

- (NSString *)resolvedCursorPath {
    if (self.configuration.firehoseCursorPath.length > 0) {
        return self.configuration.firehoseCursorPath;
    }
    return [self.configuration.dataDirectory stringByAppendingPathComponent:@"firehose.cursor"];
}

- (BOOL)startWithError:(NSError **)error {
    if (self.running) return YES;
    if (!self.configuration.firehoseEnabled) return YES;

    NSURL *url = [NSURL URLWithString:self.configuration.firehoseURL ?: @""];
    if (!url || url.host.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZBeskidFirehoseInvalidator"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"BESKID_FIREHOSE_URL is invalid"}];
        }
        return NO;
    }

    self.cursorPath = [self resolvedCursorPath];
    self.currentCursor = GZBeskidReadCursorFromFile(self.cursorPath);
    self.firehose = [[ATProtoFirehose alloc] initWithServerURL:url];
    self.subscription = [self.firehose subscribeWithCursor:self.currentCursor
                                                collections:nil
                                                  delegate:self];
    _shouldReconnect = YES;
    _reconnectAttempts = 0;
    [self.metrics setFirehoseConnected:NO];
    [self.firehose connect];
    self.running = YES;
    GZ_LOG_INFO(@"[Beskid] Firehose invalidator starting (cursor=%lld url=%@)",
                (long long)self.currentCursor, url.absoluteString);
    return YES;
}

- (void)stop {
    if (!self.running) return;
    _shouldReconnect = NO;
    [self.subscription cancel];
    [self.firehose disconnect];
    self.subscription = nil;
    self.firehose = nil;
    self.connected = NO;
    self.running = NO;
    [self.metrics setFirehoseConnected:NO];
    GZBeskidWriteCursorToFile(self.cursorPath, self.currentCursor);
}

- (void)persistCursorIfNeeded:(int64_t)seq {
    if (seq <= 0 || seq <= self.currentCursor) return;
    self.currentCursor = seq;
    GZBeskidWriteCursorToFile(self.cursorPath, seq);
}

- (void)scheduleReconnect {
    if (!_shouldReconnect || !self.running) return;

    _reconnectAttempts++;
    [self.metrics recordFirehoseReconnect];
    NSTimeInterval delay = MIN(5.0 * pow(1.5, _reconnectAttempts - 1), 60.0);
    GZ_LOG_WARN(@"[Beskid] Firehose disconnected; reconnecting in %.1fs (attempt %ld)",
                delay, (long)_reconnectAttempts);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self->_shouldReconnect || !self.running) return;
        [self.subscription cancel];
        [self.firehose disconnect];
        self.subscription = [self.firehose subscribeWithCursor:self.currentCursor
                                                    collections:nil
                                                      delegate:self];
        [self.firehose connect];
    });
}

#pragma mark - Mapping

- (BOOL)_invalidateRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey {
    NSError *error = nil;
    if (![self.database deleteRecordForDID:did collection:collection rkey:rkey error:&error]) {
        GZ_LOG_WARN(@"[Beskid] Failed to invalidate record %@/%@ for %@: %@",
                    collection, rkey, did, error.localizedDescription);
        [self.metrics recordFirehoseInvalidationApplied:@"dropped"];
        return NO;
    }
    [self.metrics recordFirehoseInvalidation:@"commit"];
    [self.metrics recordFirehoseInvalidationApplied:@"precise"];
    [self.metrics markInvalidationForDID:did];
    return YES;
}

- (void)handleCommitEvent:(ATProtoFirehoseCommitEvent *)event {
    NSString *did = event.repo;
    if (did.length == 0) {
        [self.metrics recordFirehoseParseError];
        return;
    }
    [self.metrics recordFirehoseEventReceived:@"commit"];
    NSTimeInterval t0 = [NSDate timeIntervalSinceReferenceDate];
    BOOL recordedLatency = NO;

    BOOL sawUnknownOp = NO;
    for (NSDictionary *op in event.ops ?: @[]) {
        if (![op isKindOfClass:[NSDictionary class]]) {
            sawUnknownOp = YES;
            continue;
        }
        NSString *path = op[@"path"];
        if (![path isKindOfClass:[NSString class]] || path.length == 0) {
            sawUnknownOp = YES;
            continue;
        }
        NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
        NSString *collection = parts.count > 0 ? parts[0] : @"";
        NSString *rkey = parts.count > 1 ? parts[1] : @"";
        if (collection.length == 0 || rkey.length == 0) {
            sawUnknownOp = YES;
            continue;
        }
        if ([self _invalidateRecordForDID:did collection:collection rkey:rkey] && !recordedLatency) {
            int64_t ms = (int64_t)(([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
            [self.metrics recordFirehosePurgeLatencyMillis:ms];
            recordedLatency = YES;
        }
    }

    if (sawUnknownOp) {
        NSError *error = nil;
        if ([self.database deleteAllRecordsForDID:did error:&error]) {
            [self.metrics recordFirehoseInvalidation:@"commit"];
            [self.metrics recordFirehoseInvalidationApplied:@"fallback"];
            [self.metrics markInvalidationForDID:did];
            if (!recordedLatency) {
                int64_t ms = (int64_t)(([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
                [self.metrics recordFirehosePurgeLatencyMillis:ms];
            }
        } else {
            [self.metrics recordFirehoseInvalidationApplied:@"dropped"];
            GZ_LOG_WARN(@"[Beskid] Failed conservative record purge for %@: %@",
                        did, error.localizedDescription);
        }
    }

    [self persistCursorIfNeeded:event.seq];
}

- (void)handleIdentityEvent:(ATProtoFirehoseIdentityEvent *)event {
    if (event.did.length == 0) {
        [self.metrics recordFirehoseParseError];
        return;
    }
    [self.metrics recordFirehoseEventReceived:@"identity"];
    NSTimeInterval t0 = [NSDate timeIntervalSinceReferenceDate];
    NSError *error = nil;
    if ([self.database deleteIdentityForDID:event.did error:&error]) {
        [self.metrics recordFirehoseInvalidation:@"identity"];
        [self.metrics recordFirehoseInvalidationApplied:@"precise"];
        [self.metrics markInvalidationForDID:event.did];
        int64_t ms = (int64_t)(([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
        [self.metrics recordFirehosePurgeLatencyMillis:ms];
    } else {
        [self.metrics recordFirehoseInvalidationApplied:@"dropped"];
        GZ_LOG_WARN(@"[Beskid] Failed to invalidate identity for %@: %@",
                    event.did, error.localizedDescription);
    }
    [self persistCursorIfNeeded:event.seq];
}

- (void)handleAccountEvent:(ATProtoFirehoseAccountEvent *)event {
    if (event.did.length == 0) {
        [self.metrics recordFirehoseParseError];
        return;
    }

    BOOL shouldPurge = !event.active;
    if ([event.status isKindOfClass:[NSString class]]) {
        NSString *status = event.status.lowercaseString;
        if ([status isEqualToString:@"takendown"] ||
            [status isEqualToString:@"suspended"] ||
            [status isEqualToString:@"deactivated"]) {
            shouldPurge = YES;
        }
    }
    if (!shouldPurge) {
        [self persistCursorIfNeeded:event.seq];
        return;
    }

    [self.metrics recordFirehoseEventReceived:@"account"];
    NSTimeInterval t0 = [NSDate timeIntervalSinceReferenceDate];
    NSError *error = nil;
    (void)[self.database deleteAllRecordsForDID:event.did error:&error];
    if ([self.database deleteIdentityForDID:event.did error:&error]) {
        [self.metrics recordFirehoseInvalidation:@"account"];
        [self.metrics recordFirehoseInvalidationApplied:@"precise"];
        [self.metrics markInvalidationForDID:event.did];
        int64_t ms = (int64_t)(([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
        [self.metrics recordFirehosePurgeLatencyMillis:ms];
    } else {
        [self.metrics recordFirehoseInvalidationApplied:@"dropped"];
    }
    [self persistCursorIfNeeded:event.seq];
}

#pragma mark - FirehoseSubscriptionDelegate

- (void)firehoseSubscriptionDidConnect:(ATProtoFirehoseSubscription *)subscription {
    self.connected = YES;
    _reconnectAttempts = 0;
    [self.metrics setFirehoseConnected:YES];
    GZ_LOG_INFO(@"[Beskid] Firehose connected (cursor=%lld)", (long long)self.currentCursor);
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription
        didReceiveCommitEvent:(ATProtoFirehoseCommitEvent *)event {
    [self handleCommitEvent:event];
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription
       didReceiveIdentityEvent:(ATProtoFirehoseIdentityEvent *)event {
    [self handleIdentityEvent:event];
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription
       didReceiveAccountEvent:(ATProtoFirehoseAccountEvent *)event {
    [self handleAccountEvent:event];
}

- (void)firehoseSubscription:(ATProtoFirehoseSubscription *)subscription
           didCloseWithError:(NSError *)error {
    self.connected = NO;
    [self.metrics setFirehoseConnected:NO];
    GZBeskidWriteCursorToFile(self.cursorPath, self.currentCursor);
    NSNumber *closeCode = error.userInfo[FirehoseCloseCodeKey];
    NSString *closeReason = error.userInfo[FirehoseCloseReasonKey] ?: error.localizedDescription;
    BOOL backpressure = FirehoseErrorIsBackpressureClose(error);
    if (error) {
        GZ_LOG_WARN(@"[Beskid] Firehose closed code=%@ reason=%@ backpressure=%@ cursor=%lld",
                    closeCode ?: @"-",
                    closeReason ?: @"",
                    backpressure ? @"YES" : @"NO",
                    (long long)self.currentCursor);
    } else {
        GZ_LOG_INFO(@"[Beskid] Firehose closed cleanly (cursor=%lld)", (long long)self.currentCursor);
    }
    [self scheduleReconnect];
}

@end

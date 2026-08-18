// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayIngressConfiguration.h"
#include <errno.h>
#include <stdlib.h>

NSString * const RelayIngressConfigurationErrorDomain = @"com.atproto.relay.ingress.configuration";

// Generous ceiling for shardCount: this bounds a per-DID shard executor pool on a single host,
// so it must stay well above defaultConfiguration's 4 while still ruling out pathological values.
static const NSUInteger kRelayIngressMaxShardCount = 256;

static uint64_t RelayIngressParsePositiveUInt64(NSString *value, NSError **error) {
    if (value.length == 0) {
        return 0;
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([value rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeOverflow
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ingress limit must be a positive integer"}];
        }
        return 0;
    }
    errno = 0;
    unsigned long long parsed = strtoull(value.UTF8String, NULL, 10);
    if (errno == ERANGE) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeOverflow
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ingress limit overflowed uint64_t"}];
        }
        return 0;
    }
    if (parsed == 0) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeOverflow
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ingress limit must be a positive integer"}];
        }
        return 0;
    }
    return (uint64_t)parsed;
}

// Parses a positive uint64_t and additionally rejects values that would truncate when narrowed
// to NSUInteger (relevant on platforms where NSUInteger is 32-bit).
static NSUInteger RelayIngressParsePositiveUIntegerValue(NSString *value, NSError **error) {
    uint64_t parsed = RelayIngressParsePositiveUInt64(value, error);
    if (parsed == 0) {
        return 0;
    }
    if (parsed > (uint64_t)NSUIntegerMax) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeOverflow
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ingress limit exceeds platform NSUInteger range"}];
        }
        return 0;
    }
    return (NSUInteger)parsed;
}

@interface ATProtoRelayIngressConfiguration ()
@property (nonatomic, assign, readwrite) NSUInteger maxEventCount;
@property (nonatomic, assign, readwrite) uint64_t maxByteCount;
@property (nonatomic, assign, readwrite) NSUInteger lowEventWatermark;
@property (nonatomic, assign, readwrite) uint64_t lowByteWatermark;
@property (nonatomic, assign, readwrite) NSUInteger highEventWatermark;
@property (nonatomic, assign, readwrite) uint64_t highByteWatermark;
@property (nonatomic, assign, readwrite) NSUInteger shardCount;
@property (nonatomic, assign, readwrite) BOOL boundedIngressEnabled;
- (instancetype)initUnchecked NS_DESIGNATED_INITIALIZER;
@end

@implementation ATProtoRelayIngressConfiguration

- (instancetype)initUnchecked {
    return [super init];
}

// High watermark defaults sit at 7/8 (87.5%) of max: 1792 of 2048 events, 56 MiB of the 64 MiB
// byte cap. That leaves 256 events / 8 MiB of real headroom below the hard cap for the pause
// signal (onHighWatermark -> RelayClient.pauseReading) to reach the upstream and take effect
// before admission starts rejecting frames outright — see finding F3 in
// docs/plans/workstreams/17-zuk-relay-resource-bounds/phase-38-review-remediation.md. The low
// watermark stays at 50% of max (1024 events / 32 MiB) so pause and resume are separated by a
// wide hysteresis band and do not thrash on small size fluctuations around either threshold.
+ (instancetype)defaultConfiguration {
    return [self configurationWithMaxEventCount:2048
                                   maxByteCount:64ULL * 1024ULL * 1024ULL
                                lowEventWatermark:1024
                                  lowByteWatermark:32ULL * 1024ULL * 1024ULL
                               highEventWatermark:1792
                                 highByteWatermark:56ULL * 1024ULL * 1024ULL
                                        shardCount:4
                             boundedIngressEnabled:YES
                                             error:NULL];
}

+ (nullable instancetype)configurationFromEnvironment:(NSError * _Nullable * _Nullable)error {
    NSDictionary<NSString *, NSString *> *env = [NSProcessInfo processInfo].environment;
    BOOL legacyIngress = [env[@"RELAY_LEGACY_INGRESS"] boolValue] ||
        [env[@"RELAY_LEGACY_INGRESS"] isEqualToString:@"1"];

    NSUInteger maxEvents = 2048;
    uint64_t maxBytes = 64ULL * 1024ULL * 1024ULL;
    NSUInteger shards = 4;

    if (env[@"RELAY_INGRESS_MAX_EVENTS"].length > 0) {
        maxEvents = RelayIngressParsePositiveUIntegerValue(env[@"RELAY_INGRESS_MAX_EVENTS"], error);
        if (!maxEvents) return nil;
    }
    if (env[@"RELAY_INGRESS_MAX_BYTES"].length > 0) {
        maxBytes = RelayIngressParsePositiveUInt64(env[@"RELAY_INGRESS_MAX_BYTES"], error);
        if (!maxBytes) return nil;
    }

    // Low/high defaults scale with the resolved max (50% / 87.5%, matching
    // defaultConfiguration's ratios) rather than fixed absolute values. Fixed absolutes broke
    // as soon as only RELAY_INGRESS_MAX_* was overridden to something smaller than the old
    // constants: e.g. a 1 MiB override for maxBytes against a hardcoded 56 MiB high-byte
    // default tripped the "high must stay below max" validation below even though the caller
    // never touched the watermark knobs at all.
    NSUInteger lowEvents = maxEvents / 2;
    uint64_t lowBytes = maxBytes / 2;
    NSUInteger highEvents = maxEvents - (maxEvents / 8);
    uint64_t highBytes = maxBytes - (maxBytes / 8);

    if (env[@"RELAY_INGRESS_LOW_EVENTS"].length > 0) {
        lowEvents = RelayIngressParsePositiveUIntegerValue(env[@"RELAY_INGRESS_LOW_EVENTS"], error);
        if (!lowEvents) return nil;
    }
    if (env[@"RELAY_INGRESS_LOW_BYTES"].length > 0) {
        lowBytes = RelayIngressParsePositiveUInt64(env[@"RELAY_INGRESS_LOW_BYTES"], error);
        if (!lowBytes) return nil;
    }
    if (env[@"RELAY_INGRESS_HIGH_EVENTS"].length > 0) {
        highEvents = RelayIngressParsePositiveUIntegerValue(env[@"RELAY_INGRESS_HIGH_EVENTS"], error);
        if (!highEvents) return nil;
    }
    if (env[@"RELAY_INGRESS_HIGH_BYTES"].length > 0) {
        highBytes = RelayIngressParsePositiveUInt64(env[@"RELAY_INGRESS_HIGH_BYTES"], error);
        if (!highBytes) return nil;
    }
    if (env[@"RELAY_INGRESS_SHARDS"].length > 0) {
        shards = RelayIngressParsePositiveUIntegerValue(env[@"RELAY_INGRESS_SHARDS"], error);
        if (!shards) return nil;
    }

    return [self configurationWithMaxEventCount:maxEvents
                                   maxByteCount:maxBytes
                                lowEventWatermark:lowEvents
                                  lowByteWatermark:lowBytes
                               highEventWatermark:highEvents
                                 highByteWatermark:highBytes
                                        shardCount:shards
                             boundedIngressEnabled:!legacyIngress
                                             error:error];
}

+ (nullable instancetype)configurationWithMaxEventCount:(NSUInteger)maxEvents
                                           maxByteCount:(uint64_t)maxBytes
                                     lowEventWatermark:(NSUInteger)lowEvents
                                       lowByteWatermark:(uint64_t)lowBytes
                                    highEventWatermark:(NSUInteger)highEvents
                                      highByteWatermark:(uint64_t)highBytes
                                             shardCount:(NSUInteger)shardCount
                                  boundedIngressEnabled:(BOOL)boundedIngressEnabled
                                                  error:(NSError * _Nullable * _Nullable)error {
    if (maxEvents == 0 || maxBytes == 0 || shardCount == 0) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeInvalidLimits
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ingress count/byte/shard limits must be positive"}];
        }
        return nil;
    }
    if (shardCount > kRelayIngressMaxShardCount) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeInvalidLimits
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Ingress shard count must not exceed %lu",
                                                                     (unsigned long)kRelayIngressMaxShardCount]}];
        }
        return nil;
    }
    if (lowEvents >= maxEvents || lowBytes >= maxBytes) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeInvalidWatermarks
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ingress low watermarks must stay below high limits"}];
        }
        return nil;
    }
    // The high watermark must sit strictly between low and max: if it could equal max, a
    // byte-sized event that exceeds the residual headroom below max would be rejected by
    // admitEncodedBytes: before _accountedByteCount ever reached the high watermark, so the
    // pause signal would never fire (this is finding F3). If it could equal or fall below low,
    // pause and resume would be indistinguishable and the watermark would thrash.
    if (highEvents <= lowEvents || highEvents >= maxEvents ||
        highBytes <= lowBytes || highBytes >= maxBytes) {
        if (error) {
            *error = [NSError errorWithDomain:RelayIngressConfigurationErrorDomain
                                         code:RelayIngressConfigurationErrorCodeInvalidWatermarks
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Ingress high watermarks must sit strictly between low watermarks and max limits"}];
        }
        return nil;
    }

    ATProtoRelayIngressConfiguration *config = [[self alloc] initUnchecked];
    config.maxEventCount = maxEvents;
    config.maxByteCount = maxBytes;
    config.lowEventWatermark = lowEvents;
    config.lowByteWatermark = lowBytes;
    config.highEventWatermark = highEvents;
    config.highByteWatermark = highBytes;
    config.shardCount = shardCount;
    config.boundedIngressEnabled = boundedIngressEnabled;
    return config;
}

@end

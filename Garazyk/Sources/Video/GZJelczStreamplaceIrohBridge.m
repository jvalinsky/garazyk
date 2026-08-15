// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/GZJelczStreamplaceIrohBridge.h"

#if TARGET_OS_LINUX
#import "Compat/PlatformShims/CommonCrypto/CommonDigest.h"
#else
#import <CommonCrypto/CommonDigest.h>
#endif
#import "Core/GZHTTPClient.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"
#import "Video/GZJelczIrohSidecarURL.h"
#import "Video/GZJelczPeerProviderIndex.h"

NSErrorDomain const GZJelczStreamplaceIrohBridgeErrorDomain =
    @"GZJelczStreamplaceIrohBridgeErrorDomain";

static const NSUInteger kGZJelczStreamplaceIrohBridgeDefaultSegmentBytes = 4ULL * 1024ULL * 1024ULL;
static const NSTimeInterval kGZJelczStreamplaceIrohBridgeDefaultOriginAge = 300.0;
static const NSUInteger kGZJelczStreamplaceIrohBridgeMaximumSessionIDLength = 512;

@interface GZJelczStreamplaceIrohBridgeEvidence ()
- (instancetype)initWithSessionID:(NSString *)sessionID
                 ticketFingerprint:(NSString *)ticketFingerprint
                     contentSHA256:(NSString *)contentSHA256
                      contentBytes:(NSUInteger)contentBytes;
@end

@implementation GZJelczStreamplaceIrohBridgeEvidence

- (instancetype)initWithSessionID:(NSString *)sessionID
                 ticketFingerprint:(NSString *)ticketFingerprint
                     contentSHA256:(NSString *)contentSHA256
                      contentBytes:(NSUInteger)contentBytes {
    self = [super init];
    if (self) {
        _sessionID = [sessionID copy];
        _ticketFingerprint = [ticketFingerprint copy];
        _contentSHA256 = [contentSHA256 copy];
        _contentBytes = contentBytes;
        _structurallyValid = YES;
    }
    return self;
}

@end

static BOOL GZJelczStreamplaceIrohBridgeTruthy(NSString * _Nullable value) {
    if (value.length == 0) {
        return NO;
    }
    static NSSet<NSString *> *truthy;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        truthy = [NSSet setWithObjects:@"1", @"true", @"yes", @"on", nil];
    });
    return [truthy containsObject:value.lowercaseString];
}

static uint32_t GZJelczStreamplaceIrohBridgeReadU32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
        ((uint32_t)bytes[2] << 8) | bytes[3];
}

static BOOL GZJelczStreamplaceIrohBridgeTypeEquals(const uint8_t *bytes, const char type[4]) {
    return memcmp(bytes, type, 4) == 0;
}

static NSError *GZJelczStreamplaceIrohBridgeError(GZJelczStreamplaceIrohBridgeErrorCode code,
                                                   NSString *message) {
    return [NSError errorWithDomain:GZJelczStreamplaceIrohBridgeErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSString * _Nullable GZJelczStreamplaceIrohBridgeNormalizedBase(NSString *raw,
                                                                       BOOL trustLAN) {
    NSString *base = [GZJelczIrohSidecarURL normalizedHTTPBase:raw trustLan:trustLAN];
    if (base.length == 0 || !trustLAN) {
        return base;
    }
    NSURL *url = [NSURL URLWithString:base];
    // The bearer-bearing HTTP exception is narrower than generic Track A LAN
    // access: only the canonical private Compose service name is accepted.
    if (![url.host.lowercaseString isEqualToString:@"streamplace-track-b-bridge"]) {
        return nil;
    }
    return base;
}

static void GZJelczStreamplaceIrohBridgeSetError(NSError **error,
                                                  GZJelczStreamplaceIrohBridgeErrorCode code,
                                                  NSString *message) {
    if (error) {
        *error = GZJelczStreamplaceIrohBridgeError(code, message);
    }
}

static BOOL GZJelczStreamplaceIrohBridgeIsValidSessionID(NSString *sessionID) {
    if (sessionID.length == 0 || sessionID.length > kGZJelczStreamplaceIrohBridgeMaximumSessionIDLength) {
        return NO;
    }
    for (NSUInteger index = 0; index < sessionID.length; index++) {
        unichar character = [sessionID characterAtIndex:index];
        BOOL permitted = (character >= 'a' && character <= 'z') ||
            (character >= 'A' && character <= 'Z') ||
            (character >= '0' && character <= '9') || character == '-' || character == '_';
        if (!permitted) {
            return NO;
        }
    }
    return YES;
}

static NSString * _Nullable GZJelczStreamplaceIrohBridgeSHA256Fingerprint(NSData *data) {
    if (!data) {
        return nil;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *fingerprint = [NSMutableString stringWithString:@"sha256:"];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [fingerprint appendFormat:@"%02x", digest[index]];
    }
    return fingerprint;
}

static NSString * _Nullable GZJelczStreamplaceIrohBridgeTicketFingerprint(NSString *ticket) {
    return GZJelczStreamplaceIrohBridgeSHA256Fingerprint(
        [ticket dataUsingEncoding:NSUTF8StringEncoding]);
}

static BOOL GZJelczStreamplaceIrohBridgeValidateSegment(NSData *segment, NSError **error) {
    if (segment.length < 24) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                             @"MUXL segment is truncated");
        return NO;
    }
    const uint8_t *bytes = segment.bytes;
    uint32_t catalogSize = GZJelczStreamplaceIrohBridgeReadU32(bytes);
    if (catalogSize < 24 || catalogSize > segment.length ||
        !GZJelczStreamplaceIrohBridgeTypeEquals(bytes + 4, "uuid")) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                             @"MUXL segment is missing its catalog box");
        return NO;
    }
    NSData *catalogBox = [segment subdataWithRange:NSMakeRange(0, catalogSize)];
    NSError *muxlError = nil;
    if (![ATProtoMUXLBox catalogFromUUIDMuxlBox:catalogBox error:&muxlError]) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                             muxlError.localizedDescription ?: @"MUXL catalog is invalid");
        return NO;
    }

    NSUInteger offset = catalogSize;
    NSUInteger fragments = 0;
    while (offset < segment.length) {
        if (segment.length - offset < 16) {
            GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                                 @"MUXL segment ends mid-fragment");
            return NO;
        }
        uint32_t moofSize = GZJelczStreamplaceIrohBridgeReadU32(bytes + offset);
        if (moofSize < 8 || moofSize > segment.length - offset ||
            !GZJelczStreamplaceIrohBridgeTypeEquals(bytes + offset + 4, "moof")) {
            GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                                 @"MUXL fragment is missing moof");
            return NO;
        }
        NSUInteger mdatOffset = offset + moofSize;
        if (segment.length - mdatOffset < 8) {
            GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                                 @"MUXL fragment is missing mdat");
            return NO;
        }
        uint32_t mdatSize = GZJelczStreamplaceIrohBridgeReadU32(bytes + mdatOffset);
        if (mdatSize < 8 || mdatSize > segment.length - mdatOffset ||
            !GZJelczStreamplaceIrohBridgeTypeEquals(bytes + mdatOffset + 4, "mdat")) {
            GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                                 @"MUXL fragment has an invalid mdat");
            return NO;
        }
        NSData *fragment = [segment subdataWithRange:NSMakeRange(offset, moofSize + mdatSize)];
        if (![ATProtoMUXLFragment validateFragment:fragment error:&muxlError]) {
            GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                                 muxlError.localizedDescription ?: @"MUXL fragment is invalid");
            return NO;
        }
        offset = mdatOffset + mdatSize;
        fragments += 1;
    }
    if (fragments == 0) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidMUXL,
                                             @"MUXL segment has no fragments");
        return NO;
    }
    return YES;
}

@implementation GZJelczStreamplaceIrohBridge

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                      bridgeBaseURL:(NSString *)bridgeBaseURL
                    capabilityToken:(NSString *)capabilityToken
                           trustLAN:(BOOL)trustLAN
                   allowedStreamers:(NSSet<NSString *> *)allowedStreamers {
    NSParameterAssert(httpClient);
    NSString *normalized = GZJelczStreamplaceIrohBridgeNormalizedBase(bridgeBaseURL, trustLAN);
    NSString *trimmedToken = [capabilityToken stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalized.length == 0 || trimmedToken.length == 0) {
        return nil;
    }
    self = [super init];
    if (self) {
        _httpClient = httpClient;
        _bridgeBaseURL = [normalized copy];
        _capabilityToken = [trimmedToken copy];
        _allowedStreamers = [allowedStreamers copy] ?: [NSSet set];
        _maximumOriginAge = kGZJelczStreamplaceIrohBridgeDefaultOriginAge;
        _maximumSegmentBytes = kGZJelczStreamplaceIrohBridgeDefaultSegmentBytes;
        _timeout = 10.0;
    }
    return self;
}

+ (BOOL)isEnabledInEnvironment:(NSDictionary<NSString *,NSString *> *)environment {
    return GZJelczStreamplaceIrohBridgeTruthy(environment[@"JELCZ_STREAMPLACE_IROH_BRIDGE"]);
}

+ (BOOL)trustLANInEnvironment:(NSDictionary<NSString *,NSString *> *)environment {
    return GZJelczStreamplaceIrohBridgeTruthy(
        environment[@"JELCZ_STREAMPLACE_IROH_BRIDGE_TRUST_LAN"]);
}

+ (NSString *)bridgeHTTPBaseURLFromEnvironment:(NSDictionary<NSString *,NSString *> *)environment {
    return GZJelczStreamplaceIrohBridgeNormalizedBase(
        environment[@"JELCZ_STREAMPLACE_IROH_BRIDGE_URL"],
        [self trustLANInEnvironment:environment]);
}

+ (NSUInteger)boundedByteLimitFromEnvironment:(NSDictionary<NSString *,NSString *> *)environment
                                           key:(NSString *)key
                                      fallback:(NSUInteger)fallback
                                       maximum:(NSUInteger)maximum {
    NSString *raw = environment[key];
    if (raw.length == 0 || maximum == 0) {
        return fallback;
    }
    NSScanner *scanner = [NSScanner scannerWithString:raw];
    unsigned long long parsed = 0;
    if (![scanner scanUnsignedLongLong:&parsed] || !scanner.isAtEnd || parsed == 0 || parsed > maximum) {
        return fallback;
    }
    return (NSUInteger)parsed;
}

- (NSData *)receiveSegmentFromOrigin:(GZJelczPeerProviderEntry *)origin
                                  now:(NSDate *)now
                                error:(NSError **)error {
    return [self receiveSegmentFromOrigin:origin now:now evidence:nil error:error];
}

- (NSData *)receiveSegmentFromOrigin:(GZJelczPeerProviderEntry *)origin
                                  now:(NSDate *)now
                             evidence:(GZJelczStreamplaceIrohBridgeEvidence **)evidence
                                error:(NSError **)error {
    if (evidence) {
        *evidence = nil;
    }
    if (![origin isKindOfClass:[GZJelczPeerProviderEntry class]] ||
        ![origin.source isEqualToString:@"broadcast.origin"] ||
        origin.streamerDID.length == 0 || origin.irohTicket.length == 0 || !origin.updatedAt) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorInvalidOrigin,
                                             @"A complete broadcast origin with streamer, ticket, and updatedAt is required");
        return nil;
    }
    if (![GZJelczPeerProviderIndex isDID:origin.streamerDID allowedBy:self.allowedStreamers]) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorDenied,
                                             @"Streamer is not in JELCZ_P2P_ALLOWED_STREAMERS");
        return nil;
    }
    NSDate *reference = now ?: [NSDate date];
    NSTimeInterval age = [reference timeIntervalSinceDate:origin.updatedAt];
    if (age < -60.0 || age > self.maximumOriginAge) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorStaleOrigin,
                                             @"Broadcast origin is outside the allowed freshness window");
        return nil;
    }

    NSURL *url = [NSURL URLWithString:[self.bridgeBaseURL stringByAppendingString:@"/v1/subscribe"]];
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{
        @"streamer": origin.streamerDID,
        @"irohTicket": origin.irohTicket,
        @"consentAuthorized": @YES,
    } options:0 error:nil];
    if (!url || !body) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorBridgeFailed,
                                             @"Could not construct local bridge subscription");
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = self.timeout;
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:self.capabilityToken]
       forHTTPHeaderField:@"Authorization"];

    NSHTTPURLResponse *response = nil;
    NSError *requestError = nil;
    GZHTTPClientOptions *options = [GZHTTPClientOptions defaultOptions];
    options.timeout = self.timeout;
    options.maxResponseBytes = self.maximumSegmentBytes;
    // This is narrow local IPC, not permission for general private-network egress.
    options.allowHTTP = YES;
    options.allowPrivateHosts = YES;
    options.followRedirects = NO;
    NSData *candidate = [self.httpClient sendSynchronousRequest:request
                                                        options:options
                                                       response:&response
                                                          error:&requestError];
    if (requestError && [requestError.domain isEqualToString:GZHTTPClientErrorDomain] &&
        requestError.code == GZHTTPClientErrorResponseTooLarge) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorBodyTooLarge,
                                             @"Local bridge returned a segment beyond the configured limit");
        return nil;
    }
    if (requestError || response.statusCode != 200 || !candidate) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorBridgeFailed,
                                             requestError.localizedDescription ?: @"Local bridge subscription failed");
        return nil;
    }
    NSString *sessionID = response.allHeaderFields[@"X-Jelcz-Bridge-Session"];
    if (![sessionID isKindOfClass:[NSString class]]) {
        sessionID = response.allHeaderFields[@"x-jelcz-bridge-session"];
    }
    if (!GZJelczStreamplaceIrohBridgeIsValidSessionID(sessionID)) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorMissingSession,
                                             @"Local bridge response is missing a valid session identifier");
        return nil;
    }
    if (candidate.length > self.maximumSegmentBytes) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorBodyTooLarge,
                                             @"Local bridge returned a segment beyond the configured limit");
        return nil;
    }
    if (!GZJelczStreamplaceIrohBridgeValidateSegment(candidate, error)) {
        return nil;
    }
    NSString *ticketFingerprint = GZJelczStreamplaceIrohBridgeTicketFingerprint(origin.irohTicket);
    NSString *contentSHA256 = GZJelczStreamplaceIrohBridgeSHA256Fingerprint(candidate);
    if (ticketFingerprint.length == 0 || contentSHA256.length == 0 || candidate.length == 0) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorAttestationRejected,
                                             @"Could not bind structural validation to bridge evidence");
        return nil;
    }
    NSURL *attestationURL = [NSURL URLWithString:[self.bridgeBaseURL
        stringByAppendingString:@"/v1/evidence/muxl-attestations"]];
    NSData *attestationBody = [NSJSONSerialization dataWithJSONObject:@{
        @"sessionId": sessionID,
        @"ticketFingerprint": ticketFingerprint,
        @"contentSha256": contentSHA256,
        @"contentBytes": @(candidate.length),
        @"muxlStructuralValidation": @YES,
    } options:0 error:nil];
    if (!attestationURL || !attestationBody) {
        GZJelczStreamplaceIrohBridgeSetError(error, GZJelczStreamplaceIrohBridgeErrorAttestationRejected,
                                             @"Could not construct local bridge MUXL attestation");
        return nil;
    }
    NSMutableURLRequest *attestationRequest = [NSMutableURLRequest requestWithURL:attestationURL];
    attestationRequest.HTTPMethod = @"POST";
    attestationRequest.timeoutInterval = self.timeout;
    attestationRequest.HTTPBody = attestationBody;
    [attestationRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [attestationRequest setValue:[@"Bearer " stringByAppendingString:self.capabilityToken]
        forHTTPHeaderField:@"Authorization"];
    NSHTTPURLResponse *attestationResponse = nil;
    NSError *attestationError = nil;
    [self.httpClient sendSynchronousRequest:attestationRequest
                                    options:options
                                   response:&attestationResponse
                                      error:&attestationError];
    if (attestationError || attestationResponse.statusCode != 204) {
        GZJelczStreamplaceIrohBridgeSetError(error,
                                             GZJelczStreamplaceIrohBridgeErrorAttestationRejected,
                                             attestationError.localizedDescription ?:
                                             @"Local bridge rejected MUXL evidence attestation");
        return nil;
    }
    if (evidence) {
        *evidence = [[GZJelczStreamplaceIrohBridgeEvidence alloc] initWithSessionID:sessionID
                                                                    ticketFingerprint:ticketFingerprint
                                                                       contentSHA256:contentSHA256
                                                                         contentBytes:candidate.length];
    }
    return candidate;
}

@end

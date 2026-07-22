// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/PLCAuditor.h"
#import "PLC/PLCDIDKey.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Auth/PDSKeyProtocol.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Debug/GZLogger.h"
#import "PLC/PLCMetrics.h"
#import "PLC/PLCConstants.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import <Security/Security.h>
#endif
#if __has_include(<openssl/ec.h>)
#import <openssl/ec.h>
#import <openssl/obj_mac.h>
#endif

static NSUInteger const kPLCHourLimit = 10;
static NSUInteger const kPLCDayLimit = 30;
static NSUInteger const kPLCWeekLimit = 100;

static NSString *PLCEnsureHttpPrefix(NSString *value) {
    if ([value hasPrefix:@"http://"] || [value hasPrefix:@"https://"]) {
        return value;
    }
    return [NSString stringWithFormat:@"https://%@", value];
}

static NSString *PLCEnsureAtprotoPrefix(NSString *value) {
    if ([value hasPrefix:@"at://"]) {
        return value;
    }
    NSString *stripped = [value stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    stripped = [stripped stringByReplacingOccurrencesOfString:@"https://" withString:@""];
    return [NSString stringWithFormat:@"at://%@", stripped];
}

static NSData *PLCBase64URLDecode(NSString *string) {
    if (!string) {
        return nil;
    }
    if ([string hasSuffix:@"="]) {
        return nil;
    }
    NSMutableString *base64 = [string mutableCopy];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        [base64 appendString:[@"====" substringToIndex:(4 - remainder)]];
    }
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
    base64 = [[base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

@interface PLCAuditor ()
@property (nonatomic, strong) id<PLCStore> store;
@property (nonatomic, assign) NSUInteger hourLimit;
@property (nonatomic, assign) NSUInteger dayLimit;
@property (nonatomic, assign) NSUInteger weekLimit;
@end

@implementation PLCAuditor

- (instancetype)initWithStore:(id<PLCStore>)store {
    self = [super init];
    if (self) {
        _store = store;

        // Allow override via environment variables for testing
        NSDictionary *env = [[NSProcessInfo processInfo] environment];
        _hourLimit = [self _limitFromEnv:env[@"PLC_HOURLY_LIMIT"] default:kPLCHourLimit];
        _dayLimit = [self _limitFromEnv:env[@"PLC_DAILY_LIMIT"] default:kPLCDayLimit];
        _weekLimit = [self _limitFromEnv:env[@"PLC_WEEKLY_LIMIT"] default:kPLCWeekLimit];
    }
    return self;
}

- (NSUInteger)_limitFromEnv:(NSString *)value default:(NSUInteger)defaultValue {
    if (!value || value.length == 0) return defaultValue;
    NSInteger parsed = [value integerValue];
    return (parsed > 0) ? (NSUInteger)parsed : defaultValue;
}

- (BOOL)verifyDID:(NSString *)did error:(NSError **)error {
    NSDate *startTime = [NSDate date];
    
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did includeNullified:NO error:error];
    if (!history || history.count == 0) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty history"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
        [[PLCMetrics sharedMetrics] recordResolutionLatency:latency];
        return NO;
    }

    NSError *localError = nil;
    PLCOperation *first = history.firstObject;
    NSDictionary *normalized = [self normalizedDataForOperation:first error:&localError];
    if (!normalized) {
        if (error) *error = localError;
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }
    if ([self isTombstoneOperation:first]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Tombstone cannot be genesis"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }
    if (first.prev != nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Genesis operation must have null prev"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    NSString *expectedDid = [PLCOperation calculateDIDForSignedOperation:[first toDictionary]];
    if (expectedDid.length > 0 && ![expectedDid isEqualToString:did]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Genesis DID does not match"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    NSArray<NSString *> *rotationKeys = normalized[@"rotationKeys"];
    if (![self verifySignatureForOperation:first allowedKeys:rotationKeys error:&localError]) {
        if (error) *error = localError;
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    NSString *prevCid = [self cidStringForOperation:first error:&localError];
    if (!prevCid) {
        if (error) *error = localError;
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    for (NSUInteger idx = 1; idx < history.count; idx++) {
        PLCOperation *op = history[idx];
        if (op.prev == nil || ![op.prev isKindOfClass:[NSString class]] || ![op.prev isEqualToString:prevCid]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:5
                                         userInfo:@{NSLocalizedDescriptionKey: @"Operation prev does not match history"}];
            }
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        if ([self isTombstoneOperation:op]) {
            if (idx != history.count - 1) {
                if (error) {
                    *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                                 code:6
                                             userInfo:@{NSLocalizedDescriptionKey: @"Tombstone must be last"}];
                }
                [[PLCMetrics sharedMetrics] recordVerificationFailure];
                return NO;
            }
        }

        if (![self verifySignatureForOperation:op allowedKeys:rotationKeys error:&localError]) {
            if (error) *error = localError;
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }

        if ([self isTombstoneOperation:op]) {
            break;
        }

        normalized = [self normalizedDataForOperation:op error:&localError];
        if (!normalized) {
            if (error) *error = localError;
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        rotationKeys = normalized[@"rotationKeys"];
        prevCid = [self cidStringForOperation:op error:&localError];
        if (!prevCid) {
            if (error) *error = localError;
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
    }

    [[PLCMetrics sharedMetrics] recordVerificationSuccess];
    NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
    [[PLCMetrics sharedMetrics] recordResolutionLatency:latency];
    return YES;
}

- (BOOL)verifyOperation:(PLCOperation *)op
	           proposedDate:(NSDate *)proposedDate
	          nullifiedCIDs:(NSArray<NSString *> * _Nullable __autoreleasing * _Nullable)nullified
	                  error:(NSError **)error {
    NSDate *startTime = [NSDate date];

    NSString *opType = op.data[@"type"];
    if (opType) {
        [[PLCMetrics sharedMetrics] recordOperation:opType];
    }

    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:op.did includeNullified:NO error:error];
    if (!history) {
        history = @[];
    }

    NSError *localError = nil;
    if (history.count == 0) {
        if ([self isTombstoneOperation:op]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Tombstone cannot be genesis"}];
            }
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        if (op.prev != nil) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Genesis operation must have null prev"}];
            }
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        NSString *expectedDid = [PLCOperation calculateDIDForSignedOperation:[op toDictionary]];
        if (expectedDid.length > 0 && ![expectedDid isEqualToString:op.did]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:19
                                         userInfo:@{NSLocalizedDescriptionKey: @"Genesis DID does not match"}];
            }
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        NSDictionary *normalized = [self normalizedDataForOperation:op error:&localError];
        if (!normalized) {
            if (error) *error = localError;
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        NSArray<NSString *> *rotationKeys = normalized[@"rotationKeys"];
        if (![self verifySignatureForOperation:op allowedKeys:rotationKeys error:&localError]) {
            if (error) *error = localError;
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        if (nullified) *nullified = @[];
        [[PLCMetrics sharedMetrics] recordVerificationSuccess];
        NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
        [[PLCMetrics sharedMetrics] recordResolutionLatency:latency];
        return YES;
    }

    PLCOperation *mostRecent = history.lastObject;
    if ([self isTombstoneOperation:mostRecent]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID is tombstoned"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    if (!op.prev || ![op.prev isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Operation must reference prev CID"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    NSUInteger prevIndex = NSNotFound;
    for (NSUInteger idx = 0; idx < history.count; idx++) {
        PLCOperation *existing = history[idx];
        NSString *cidString = existing.cid ?: [self cidStringForOperation:existing error:nil];
        if (cidString && [cidString isEqualToString:op.prev]) {
            prevIndex = idx;
            break;
        }
    }
    if (prevIndex == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Prev CID not found in history"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    NSArray<PLCOperation *> *opsInHistory = [history subarrayWithRange:NSMakeRange(0, prevIndex + 1)];
    NSArray<PLCOperation *> *nullifiedOps = (prevIndex + 1 < history.count)
        ? [history subarrayWithRange:NSMakeRange(prevIndex + 1, history.count - prevIndex - 1)]
        : @[];
    PLCOperation *lastOp = opsInHistory.lastObject;
    NSDictionary *lastNormalized = [self normalizedDataForOperation:lastOp error:&localError];
    if (!lastNormalized) {
        if (error) *error = localError;
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }
    NSArray<NSString *> *rotationKeys = lastNormalized[@"rotationKeys"];

    if (nullifiedOps.count == 0) {
        if (![self enforceRateLimitForHistory:history proposedDate:proposedDate error:&localError]) {
            if (error) *error = localError;
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        if (![self verifySignatureForOperation:op allowedKeys:rotationKeys error:&localError]) {
            if (error) *error = localError;
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
        if (nullified) *nullified = @[];
        [[PLCMetrics sharedMetrics] recordVerificationSuccess];
        NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
        [[PLCMetrics sharedMetrics] recordResolutionLatency:latency];
        return YES;
    }

    PLCOperation *firstNullified = nullifiedOps.firstObject;
    NSString *signedKey = [self verifySignatureForOperation:firstNullified allowedKeys:rotationKeys error:&localError];
    if (!signedKey) {
        if (error) *error = localError;
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    NSUInteger signerIndex = [rotationKeys indexOfObject:signedKey];
    if (signerIndex == NSNotFound || signerIndex == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"No more powerful rotation key available"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    NSArray<NSString *> *morePowerfulKeys = [rotationKeys subarrayWithRange:NSMakeRange(0, signerIndex)];
    if (![self verifySignatureForOperation:op allowedKeys:morePowerfulKeys error:&localError]) {
        if (error) *error = localError;
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    if (mostRecent.createdAt && [proposedDate compare:mostRecent.createdAt] != NSOrderedDescending) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Operation timestamp must be newer"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    if (firstNullified.createdAt) {
        NSTimeInterval delta = [proposedDate timeIntervalSinceDate:firstNullified.createdAt];
        if (delta > PLCRecoveryWindowSeconds) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:9
                                         userInfo:@{NSLocalizedDescriptionKey: @"Recovery window exceeded"}];
            }
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
    }

    if (nullified) {
        NSMutableArray<NSString *> *cids = [NSMutableArray array];
        for (PLCOperation *nullifiedOp in nullifiedOps) {
            NSString *cidString = nullifiedOp.cid ?: [self cidStringForOperation:nullifiedOp error:nil];
            if (cidString) {
                [cids addObject:cidString];
            }
        }
        *nullified = [cids copy];
    }

    [[PLCMetrics sharedMetrics] recordVerificationSuccess];
    NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
    [[PLCMetrics sharedMetrics] recordResolutionLatency:latency];
    return YES;
}

- (BOOL)verifyOperation:(PLCOperation *)op error:(NSError **)error {
    NSArray<NSString *> *nullified = nil;
    return [self verifyOperation:op proposedDate:[NSDate date] nullifiedCIDs:&nullified error:error];
}

- (NSData *)hashForOperationData:(NSDictionary *)data {
    NSError *error = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:data error:&error];
    if (!cbor) {
        GZ_LOG_CORE_ERROR(@"Failed to encode unsigned data to CBOR: %@", error);
        return nil;
    }
    GZ_LOG_CORE_DEBUG(@"Unsigned data for hash: %@", data);
    GZ_LOG_CORE_DEBUG(@"Unsigned CBOR bytes: %@", [CryptoUtils hexStringFromData:cbor]);
    NSData *hash = [CryptoUtils sha256:cbor];
    GZ_LOG_CORE_DEBUG(@"Calculated hash: %@", [CryptoUtils hexStringFromData:hash]);
    return hash;
}

- (BOOL)isTombstoneOperation:(PLCOperation *)op {
    return [op.data[@"type"] isEqualToString:@"plc_tombstone"];
}

- (nullable NSDictionary *)normalizedDataForOperation:(PLCOperation *)op error:(NSError **)error {
    NSString *type = op.data[@"type"];
    if ([type isEqualToString:@"plc_operation"]) {
        NSArray *rotationKeys = op.data[@"rotationKeys"];
        NSDictionary *verificationMethods = op.data[@"verificationMethods"];
        NSArray *alsoKnownAs = op.data[@"alsoKnownAs"];
        NSDictionary *services = op.data[@"services"];
        if (![rotationKeys isKindOfClass:[NSArray class]] ||
            ![verificationMethods isKindOfClass:[NSDictionary class]] ||
            ![alsoKnownAs isKindOfClass:[NSArray class]] ||
            ![services isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:10
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid plc_operation structure"}];
            }
            return nil;
        }
        return @{
            @"rotationKeys": rotationKeys,
            @"verificationMethods": verificationMethods,
            @"alsoKnownAs": alsoKnownAs,
            @"services": services
        };
    }

    if ([type isEqualToString:@"create"]) {
        NSString *signingKey = op.data[@"signingKey"];
        NSString *recoveryKey = op.data[@"recoveryKey"];
        NSString *handle = op.data[@"handle"];
        NSString *service = op.data[@"service"];
        if (![signingKey isKindOfClass:[NSString class]] ||
            ![recoveryKey isKindOfClass:[NSString class]] ||
            ![handle isKindOfClass:[NSString class]] ||
            ![service isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:11
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid create operation structure"}];
            }
            return nil;
        }
        return @{
            @"rotationKeys": @[recoveryKey, signingKey],
            @"verificationMethods": @{@"atproto": signingKey},
            @"alsoKnownAs": @[PLCEnsureAtprotoPrefix(handle)],
            @"services": @{@"atproto_pds": @{@"type": @"AtprotoPersonalDataServer",
                                             @"endpoint": PLCEnsureHttpPrefix(service)}}
        };
    }

    if (error) {
        *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                     code:12
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported operation type"}];
    }
    return nil;
}

- (nullable NSString *)cidStringForOperation:(PLCOperation *)op error:(NSError **)error {
    if (op.cid.length > 0) {
        return op.cid;
    }
    return [PLCOperation calculateCIDForOperation:[op toDictionary] error:error];
}

- (nullable NSString *)verifySignatureForOperation:(PLCOperation *)op
                                       allowedKeys:(NSArray<NSString *> *)allowedKeys
                                             error:(NSError **)error {
    NSData *sigData = PLCBase64URLDecode(op.sig);
    if (!sigData) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid signature encoding"}];
        }
        return nil;
    }
    NSDictionary *unsignedData = [self unsignedDataForOperation:op];
    NSData *opDataHash = [self hashForOperationData:unsignedData];
    if (!opDataHash) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:14
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode operation for signature"}];
        }
        return nil;
    }
    for (NSString *keyString in allowedKeys) {
        PLCDIDKey *parsedKey = [PLCDIDKey parseFromString:keyString error:nil];
        NSData *pubKey = nil;
        BOOL isP256 = NO;

        if (parsedKey) {
            pubKey = parsedKey.publicKeyBytes;
            if (parsedKey.type == PLCDIDKeyTypeP256) {
                isP256 = YES;
            }
        } else {
            // Fallback for hex string
            pubKey = [self dataFromKeyString:keyString];
        }

        if (!pubKey) continue;

        if (isP256) {
            if ([self verifyP256Signature:sigData hash:opDataHash compressedPublicKey:pubKey]) {
                return keyString;
            }
        } else {
            NSData *normalizedKey = [[Secp256k1 shared] normalizedPublicKey:pubKey error:nil];
            if (normalizedKey && [[Secp256k1 shared] verifySignature:sigData forHash:opDataHash withPublicKey:normalizedKey error:nil]) {
                return keyString;
            }
        }
    }
    if (error) {
        *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                     code:15
                                 userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed"}];
    }
    return nil;
}

- (NSDictionary *)unsignedDataForOperation:(PLCOperation *)op {
    NSMutableDictionary *data = [op.data mutableCopy] ?: [NSMutableDictionary dictionary];
    
    // Strip wrapper-level and non-operation fields defensively.
    // Per spec, "did" and "cid" are not valid operation data fields.
    // "sig" must be absent for signature verification (the unsigned bytes
    // are what gets signed, not bytes with sig:null).
    [data removeObjectForKey:@"did"];
    [data removeObjectForKey:@"cid"];
    [data removeObjectForKey:@"sig"];
    
    // Explicitly handle 'prev' field normalization for genesis operations
    id prev = op.prev ?: data[@"prev"];
    if (prev == nil || prev == [NSNull null]) {
        data[@"prev"] = [NSNull null];
    } else {
        data[@"prev"] = prev;
    }
    
    // Ensure all required fields are present in the reconstruction
    if (!data[@"type"]) data[@"type"] = @"plc_operation";
    
    return [data copy];
}

- (BOOL)enforceRateLimitForHistory:(NSArray<PLCOperation *> *)history
                      proposedDate:(NSDate *)proposedDate
                             error:(NSError **)error {
    NSDate *hourAgo = [proposedDate dateByAddingTimeInterval:-3600];
    NSDate *dayAgo = [proposedDate dateByAddingTimeInterval:-86400];
    NSDate *weekAgo = [proposedDate dateByAddingTimeInterval:-(86400 * 7)];

    NSUInteger withinHour = 0;
    NSUInteger withinDay = 0;
    NSUInteger withinWeek = 0;

    for (PLCOperation *op in history) {
        NSDate *timestamp = op.createdAt ?: proposedDate;
        if ([timestamp compare:weekAgo] == NSOrderedDescending) {
            withinWeek++;
        }
        if ([timestamp compare:dayAgo] == NSOrderedDescending) {
            withinDay++;
        }
        if ([timestamp compare:hourAgo] == NSOrderedDescending) {
            withinHour++;
        }
    }

    if (withinHour >= self.hourLimit) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:16
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many operations within last hour"}];
        }
        return NO;
    }
    if (withinDay >= self.dayLimit) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:17
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many operations within last day"}];
        }
        return NO;
    }
    if (withinWeek >= self.weekLimit) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:18
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many operations within last week"}];
        }
        return NO;
    }

    return YES;
}

- (NSData *)dataFromKeyString:(NSString *)keyString {
    if (!keyString || ![keyString isKindOfClass:[NSString class]]) return nil;
    if ([keyString hasPrefix:@"did:key:"]) {
        // PLCDIDKey handles varint multicodec decoding for both secp256k1 (0xe7) and P-256 (0x1200)
        PLCDIDKey *parsed = [PLCDIDKey parseFromString:keyString error:nil];
        if (parsed) return parsed.publicKeyBytes;
    }
    return [self dataFromHexString:keyString];
}

// Convert raw r||s (64 bytes) to DER-encoded ECDSA signature for SecKey APIs.
static NSData *PLCDEREncodeRawSignature(NSData *rawSig) {
    if (rawSig.length != 64) return nil;
    const uint8_t *bytes = rawSig.bytes;

    // r and s are the two 32-byte halves
    const uint8_t *rBytes = bytes;
    const uint8_t *sBytes = bytes + 32;

    // Strip leading zeros (DER INTEGER must be minimal), but keep at least one byte
    NSUInteger rStart = 0, sStart = 0;
    while (rStart < 31 && rBytes[rStart] == 0x00) rStart++;
    while (sStart < 31 && sBytes[sStart] == 0x00) sStart++;

    NSUInteger rLen = 32 - rStart;
    NSUInteger sLen = 32 - sStart;

    // If high bit set, prepend 0x00 to keep integer positive
    BOOL rPad = (rBytes[rStart] & 0x80) != 0;
    BOOL sPad = (sBytes[sStart] & 0x80) != 0;

    NSUInteger rTotalLen = rLen + (rPad ? 1 : 0);
    NSUInteger sTotalLen = sLen + (sPad ? 1 : 0);
    NSUInteger seqBodyLen = 2 + rTotalLen + 2 + sTotalLen;

    NSMutableData *der = [NSMutableData dataWithCapacity:2 + seqBodyLen];
    uint8_t b;

    b = 0x30; [der appendBytes:&b length:1];            // SEQUENCE
    b = (uint8_t)seqBodyLen; [der appendBytes:&b length:1];

    b = 0x02; [der appendBytes:&b length:1];            // INTEGER r
    b = (uint8_t)rTotalLen; [der appendBytes:&b length:1];
    if (rPad) { b = 0x00; [der appendBytes:&b length:1]; }
    [der appendBytes:rBytes + rStart length:rLen];

    b = 0x02; [der appendBytes:&b length:1];            // INTEGER s
    b = (uint8_t)sTotalLen; [der appendBytes:&b length:1];
    if (sPad) { b = 0x00; [der appendBytes:&b length:1]; }
    [der appendBytes:sBytes + sStart length:sLen];

    return [der copy];
}

static NSData *PLCUncompressP256PublicKeyOpenSSL(NSData *compressedKey) {
#if __has_include(<openssl/ec.h>)
    if (compressedKey.length != 33) {
        return nil;
    }
    const uint8_t *bytes = compressedKey.bytes;
    if (bytes[0] != 0x02 && bytes[0] != 0x03) {
        return nil;
    }

    EC_KEY *ecKey = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!ecKey) {
        return nil;
    }

    const EC_GROUP *group = EC_KEY_get0_group(ecKey);
    EC_POINT *point = group ? EC_POINT_new(group) : NULL;
    if (!group || !point ||
        EC_POINT_oct2point(group, point, compressedKey.bytes, compressedKey.length, NULL) != 1) {
        if (point) EC_POINT_free(point);
        EC_KEY_free(ecKey);
        return nil;
    }

    size_t pointLen = EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, NULL, 0, NULL);
    NSMutableData *result = nil;
    if (pointLen == 65) {
        result = [NSMutableData dataWithLength:pointLen];
        if (EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, result.mutableBytes, pointLen, NULL) != pointLen) {
            result = nil;
        }
    }

    EC_POINT_free(point);
    EC_KEY_free(ecKey);
    return result;
#else
    (void)compressedKey;
    return nil;
#endif
}

typedef struct {
    uint32_t w[8]; // Little-endian 32-bit words
} PLCP256Field;

static const PLCP256Field kPLCP256Prime = { .w = { 0xffffffffu, 0xffffffffu, 0xffffffffu, 0x00000000u, 0x00000000u, 0x00000000u, 0x00000001u, 0xffffffffu } };
static const PLCP256Field kPLCP256B = { .w = { 0x27d2604bu, 0x3bce3c3eu, 0xcc53b0f6u, 0x651d06b0u, 0x769886bcu, 0xb3ebbd55u, 0xaa3a93e7u, 0x5ac635d8u } };
static const PLCP256Field kPLCP256TwoPow256ModP = { .w = { 0x00000001u, 0x00000000u, 0x00000000u, 0xffffffffu, 0xffffffffu, 0xffffffffu, 0xfffffffeu, 0x00000000u } }; // 2^256 mod p
static const uint32_t kPLCP256SqrtExp[(8)] = { 0x00000000u, 0x00000000u, 0x40000000u, 0x00000000u, 0x00000000u, 0x40000000u, 0xc0000000u, 0x3fffffffu }; // (p+1)/4

static int PLCP256Cmp(const PLCP256Field *a, const PLCP256Field *b) {
    for (int i = 7; i >= 0; i--) {
        if (a->w[i] < b->w[i]) return -1;
        if (a->w[i] > b->w[i]) return 1;
    }
    return 0;
}

static BOOL PLCP256IsZero(const PLCP256Field *a) {
    uint32_t acc = 0;
    for (int i = 0; i < 8; i++) acc |= a->w[i];
    return acc == 0;
}

static BOOL PLCP256Equal(const PLCP256Field *a, const PLCP256Field *b) {
    uint32_t acc = 0;
    for (int i = 0; i < 8; i++) acc |= (a->w[i] ^ b->w[i]);
    return acc == 0;
}

static PLCP256Field PLCP256AddMod(const PLCP256Field *a, const PLCP256Field *b) {
    PLCP256Field r;
    uint64_t carry = 0;
    for (int i = 0; i < 8; i++) {
        uint64_t sum = (uint64_t)a->w[i] + (uint64_t)b->w[i] + carry;
        r.w[i] = (uint32_t)sum;
        carry = sum >> 32;
    }
    if (carry) {
        // Fold the implicit +2^256 using 2^256 ≡ (2^256 mod p)
        carry = 0;
        for (int i = 0; i < 8; i++) {
            uint64_t sum = (uint64_t)r.w[i] + (uint64_t)kPLCP256TwoPow256ModP.w[i] + carry;
            r.w[i] = (uint32_t)sum;
            carry = sum >> 32;
        }
    } else if (PLCP256Cmp(&r, &kPLCP256Prime) >= 0) {
        // r -= p
        uint64_t borrow = 0;
        for (int i = 0; i < 8; i++) {
            uint64_t ai = (uint64_t)r.w[i];
            uint64_t bi = (uint64_t)kPLCP256Prime.w[i];
            uint64_t tmp = ai - bi - borrow;
            r.w[i] = (uint32_t)tmp;
            borrow = borrow ? (ai <= bi) : (ai < bi);
        }
    }
    return r;
}

static PLCP256Field PLCP256SubMod(const PLCP256Field *a, const PLCP256Field *b) {
    PLCP256Field r;
    uint64_t borrow = 0;
    for (int i = 0; i < 8; i++) {
        uint64_t ai = (uint64_t)a->w[i];
        uint64_t bi = (uint64_t)b->w[i];
        uint64_t tmp = ai - bi - borrow;
        r.w[i] = (uint32_t)tmp;
        borrow = borrow ? (ai <= bi) : (ai < bi);
    }
    if (borrow) {
        // We computed (a - b + 2^256). Convert to (a - b + p) by subtracting 2^256 mod p.
        borrow = 0;
        for (int i = 0; i < 8; i++) {
            uint64_t ai = (uint64_t)r.w[i];
            uint64_t bi = (uint64_t)kPLCP256TwoPow256ModP.w[i];
            uint64_t tmp = ai - bi - borrow;
            r.w[i] = (uint32_t)tmp;
            borrow = borrow ? (ai <= bi) : (ai < bi);
        }
    }
    return r;
}

static PLCP256Field PLCP256NegMod(const PLCP256Field *a) {
    if (PLCP256IsZero(a)) {
        return *a;
    }
    return PLCP256SubMod(&kPLCP256Prime, a);
}

static PLCP256Field PLCP256Reduce512(const uint32_t in[16]) {
    __int128 r[16];
    for (int i = 0; i < 16; i++) {
        r[i] = (__int128)in[i];
    }

    // Reduce using b^8 ≡ b^7 - b^6 - b^3 + 1 (mod p), where b = 2^32.
    for (int i = 15; i >= 8; i--) {
        __int128 c = r[i];
        if (c == 0) continue;
        r[i] = 0;
        r[i - 8] += c;
        r[i - 1] += c;
        r[i - 2] -= c;
        r[i - 5] -= c;
    }

    // Normalize words and fold any remaining carry from the implicit word 8.
    for (int iter = 0; iter < 3; iter++) {
        __int128 carry = 0;
        for (int i = 0; i < 8; i++) {
            __int128 val = r[i] + carry;
            uint32_t digit = (uint32_t)val;
            r[i] = digit;
            carry = val >> 32;
        }

        if (carry == 0) {
            break;
        }

        // Fold carry as coefficient of b^8.
        r[0] += carry;
        r[7] += carry;
        r[6] -= carry;
        r[3] -= carry;
    }

    PLCP256Field out;
    for (int i = 0; i < 8; i++) {
        out.w[i] = (uint32_t)r[i];
    }

    while (PLCP256Cmp(&out, &kPLCP256Prime) >= 0) {
        out = PLCP256SubMod(&out, &kPLCP256Prime);
    }
    return out;
}

static PLCP256Field PLCP256MulMod(const PLCP256Field *a, const PLCP256Field *b) {
    unsigned __int128 accum[16] = {0};
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
            accum[i + j] += (unsigned __int128)a->w[i] * (unsigned __int128)b->w[j];
        }
    }

    uint32_t product[16];
    unsigned __int128 carry = 0;
    for (int i = 0; i < 16; i++) {
        unsigned __int128 val = accum[i] + carry;
        product[i] = (uint32_t)val;
        carry = val >> 32;
    }

    return PLCP256Reduce512(product);
}

static PLCP256Field PLCP256PowMod(const PLCP256Field *base, const uint32_t expWords[8]) {
    PLCP256Field result = { .w = { 1u, 0u, 0u, 0u, 0u, 0u, 0u, 0u } };
    PLCP256Field power = *base;

    for (int word = 7; word >= 0; word--) {
        uint32_t w = expWords[word];
        for (int bit = 31; bit >= 0; bit--) {
            result = PLCP256MulMod(&result, &result);
            if ((w >> bit) & 1u) {
                result = PLCP256MulMod(&result, &power);
            }
        }
    }

    return result;
}

static void PLCP256WriteBE32(uint8_t *out, uint32_t value) {
    out[0] = (uint8_t)((value >> 24) & 0xff);
    out[1] = (uint8_t)((value >> 16) & 0xff);
    out[2] = (uint8_t)((value >> 8) & 0xff);
    out[3] = (uint8_t)(value & 0xff);
}

static PLCP256Field PLCP256FromBytesBE(const uint8_t bytes[32]) {
    PLCP256Field out;
    for (int i = 0; i < 8; i++) {
        const uint8_t *p = bytes + (7 - i) * 4;
        out.w[i] = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
    }
    return out;
}

static void PLCP256ToBytesBE(const PLCP256Field *value, uint8_t out[32]) {
    for (int i = 0; i < 8; i++) {
        PLCP256WriteBE32(out + (7 - i) * 4, value->w[i]);
    }
}

static BOOL PLCP256UncompressPublicKey(const uint8_t compressed[33], uint8_t outUncompressed[65]) {
    const uint8_t prefix = compressed[0];
    if (prefix != 0x02 && prefix != 0x03) {
        return NO;
    }

    PLCP256Field x = PLCP256FromBytesBE(compressed + 1);
    if (PLCP256Cmp(&x, &kPLCP256Prime) >= 0) {
        return NO;
    }

    // rhs = x^3 - 3x + b  (mod p), where a = -3 for P-256.
    PLCP256Field x2 = PLCP256MulMod(&x, &x);
    PLCP256Field x3 = PLCP256MulMod(&x2, &x);

    PLCP256Field twoX = PLCP256AddMod(&x, &x);
    PLCP256Field threeX = PLCP256AddMod(&twoX, &x);
    PLCP256Field rhs = PLCP256SubMod(&x3, &threeX);
    rhs = PLCP256AddMod(&rhs, &kPLCP256B);

    PLCP256Field y = PLCP256PowMod(&rhs, kPLCP256SqrtExp);
    PLCP256Field y2 = PLCP256MulMod(&y, &y);
    if (!PLCP256Equal(&y2, &rhs)) {
        return NO;
    }

    BOOL shouldBeOdd = (prefix == 0x03);
    BOOL isOdd = (y.w[0] & 1u) != 0;
    if (isOdd != shouldBeOdd) {
        y = PLCP256NegMod(&y);
    }

    outUncompressed[0] = 0x04;
    memcpy(outUncompressed + 1, compressed + 1, 32);
    uint8_t yBytes[32];
    PLCP256ToBytesBE(&y, yBytes);
    memcpy(outUncompressed + 33, yBytes, 32);
    return YES;
}

- (BOOL)verifyP256Signature:(NSData *)rawSig hash:(NSData *)hash compressedPublicKey:(NSData *)pubKey {
    // Signature must be 64 bytes (raw r||s format)
    if (!rawSig || rawSig.length != 64) return NO;

    // Hash must be 32 bytes (SHA-256)
    if (!hash || hash.length != 32) return NO;

    // did:plc requires low-S canonical signatures (see AuthCryptoECDSA.h's
    // normalizeLowS discussion / https://web.plc.directory/spec/v0.1/did-plc);
    // libsecp256k1 enforces this for free on the ES256K path, but the shared
    // P-256 JOSE verifier (AuthCryptoJWK) deliberately accepts both S forms
    // per ADR 0007 (DPoP/JWT/WebAuthn callers must not reject high-S). PLC
    // operation verification is not one of those callers, so it must reject
    // non-canonical signatures explicitly here.
    if (![AuthCryptoECDSA isLowS:rawSig error:nil]) {
        return NO;
    }
    
    // Convert public key to uncompressed format if needed
    NSData *uncompressedPubKey = pubKey;
    uint8_t uncompressedBuffer[65];
    
    if (pubKey.length == 33) {
        // Prefer OpenSSL decompression when available; keep field-arithmetic fallback.
        NSData *opensslDecompressed = PLCUncompressP256PublicKeyOpenSSL(pubKey);
        if (opensslDecompressed.length == 65) {
            uncompressedPubKey = opensslDecompressed;
        } else {
            if (!PLCP256UncompressPublicKey(pubKey.bytes, uncompressedBuffer)) {
                return NO;
            }
            uncompressedPubKey = [NSData dataWithBytes:uncompressedBuffer length:65];
        }
    } else if (pubKey.length != 65) {
        return NO;
    }
    
    // Extract x and y coordinates from uncompressed format (0x04 || x || y)
    if (uncompressedPubKey.length != 65 || ((const uint8_t *)uncompressedPubKey.bytes)[0] != 0x04) {
        return NO;
    }
    
    NSData *xData = [uncompressedPubKey subdataWithRange:NSMakeRange(1, 32)];
    NSData *yData = [uncompressedPubKey subdataWithRange:NSMakeRange(33, 32)];
    
    // Build JWK
    NSDictionary *jwk = @{
        @"kty": @"EC",
        @"crv": @"P-256",
        @"x": [AuthCryptoBase64URL encode:xData],
        @"y": [AuthCryptoBase64URL encode:yData]
    };
    
    // Create public key from JWK
    NSError *keyError = nil;
    id<PDSPublicKeyProtocol> publicKey = [AuthCryptoJWK publicKeyFromJWK:jwk error:&keyError];
    if (!publicKey) {
        return NO;
    }
    
    // Verify signature using pre-computed hash (digest verification)
    NSError *verifyError = nil;
    return [publicKey verifyDigestSignature:rawSig forHash:hash error:&verifyError];
}

- (NSData *)dataFromHexString:(NSString *)hex {
    if (!hex) return nil;
    NSMutableData *data = [NSMutableData data];
    for (int i = 0; i + 1 < [hex length]; i += 2) {
        unsigned int value;
        NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]];
        [scanner scanHexInt:&value];
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    }
    return data;
}

@end

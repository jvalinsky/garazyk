#import "PLC/PLCAuditor.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"
#import "PLC/PLCMetrics.h"

static NSTimeInterval const kPLCRecoveryWindowSeconds = 72 * 60 * 60;
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
@end

@implementation PLCAuditor

- (instancetype)initWithStore:(id<PLCStore>)store {
    self = [super init];
    if (self) {
        _store = store;
    }
    return self;
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

    NSString *expectedDid = [PLCOperation calculateDIDForData:first.data];
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
          nullifiedCIDs:(NSArray<NSString *> * _Nullable *)nullified
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
        NSString *expectedDid = [PLCOperation calculateDIDForData:op.data];
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
        if (delta > kPLCRecoveryWindowSeconds) {
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
        return nil;
    }
    return [CryptoUtils sha256:cbor];
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
        NSData *pubKey = [self dataFromKeyString:keyString];
        NSData *normalizedKey = [[Secp256k1 shared] normalizedPublicKey:pubKey error:nil];
        if (normalizedKey && [[Secp256k1 shared] verifySignature:sigData forHash:opDataHash withPublicKey:normalizedKey error:nil]) {
            return keyString;
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
    if (op.prev != nil) {
        data[@"prev"] = op.prev;
    } else if (!data[@"prev"]) {
        data[@"prev"] = [NSNull null];
    }
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

    if (withinHour >= kPLCHourLimit) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:16
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many operations within last hour"}];
        }
        return NO;
    }
    if (withinDay >= kPLCDayLimit) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:17
                                     userInfo:@{NSLocalizedDescriptionKey: @"Too many operations within last day"}];
        }
        return NO;
    }
    if (withinWeek >= kPLCWeekLimit) {
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
    if ([keyString hasPrefix:@"did:key:z"]) {
        NSString *base58 = [keyString substringFromIndex:9];
        NSData *decoded = [CID base58btcDecode:base58];
        if (decoded.length > 2) {
            const uint8_t *bytes = decoded.bytes;
            // Skip 0xe7 0x01 prefix for secp256k1
            if (bytes[0] == 0xe7 && bytes[1] == 0x01) {
                return [decoded subdataWithRange:NSMakeRange(2, decoded.length - 2)];
            }
        }
        return decoded;
    }
    return [self dataFromHexString:keyString];
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

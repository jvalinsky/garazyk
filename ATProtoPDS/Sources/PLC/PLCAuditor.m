#import "PLC/PLCAuditor.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"
#import "PLC/PLCMetrics.h"

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
    
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did error:error];
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

    NSString *lastHash = nil;
    NSArray<NSString *> *authorizedKeys = nil;
    BOOL success = YES;

    for (PLCOperation *op in history) {
        NSString *opType = op.data[@"type"];
        if (opType) {
            [[PLCMetrics sharedMetrics] recordOperation:opType];
        }
        
        if (!op.prev && lastHash) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected genesis operation in middle of history"}];
            }
            success = NO;
            break;
        }
        if (op.prev && [op.prev isKindOfClass:[NSString class]]) {
            NSLog(@"[PLC AUDITOR] Loop Checking prev hash: %@ vs last: %@", op.prev, lastHash);
            if (![op.prev isEqualToString:lastHash]) {
                if (error) {
                    *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                                 code:3
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Prev hash mismatch. Expected %@, got %@", lastHash, op.prev]}];
                }
                success = NO;
                break;
            }
        }

        if (!authorizedKeys) {
            authorizedKeys = op.data[@"rotationKeys"];
        }

        BOOL sigOk = NO;
        NSData *opDataHash = [self hashForOperationData:op.data];
        NSData *sigData = [self dataFromSignatureString:op.sig];

        for (NSString *keyString in authorizedKeys) {
            NSData *pubKey = [self dataFromKeyString:keyString];
            NSData *normalizedKey = [[Secp256k1 shared] normalizedPublicKey:pubKey error:nil];
            if (normalizedKey && [[Secp256k1 shared] verifySignature:sigData forHash:opDataHash withPublicKey:normalizedKey error:nil]) {
                sigOk = YES;
                break;
            }
        }

        if (!sigOk) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:4
                                         userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed"}];
            }
            success = NO;
            break;
        }

        authorizedKeys = op.data[@"rotationKeys"];
        lastHash = [CryptoUtils hexStringFromData:opDataHash];
    }

    if (success) {
        [[PLCMetrics sharedMetrics] recordVerificationSuccess];
    } else {
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
    }
    
    NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
    [[PLCMetrics sharedMetrics] recordResolutionLatency:latency];
    
    return success;
}

- (BOOL)verifyOperation:(PLCOperation *)op error:(NSError **)error {
    NSDate *startTime = [NSDate date];
    
    NSString *opType = op.data[@"type"];
    if (opType) {
        [[PLCMetrics sharedMetrics] recordOperation:opType];
    }
    
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:op.did error:error];
    NSString *lastHash = nil;
    NSArray<NSString *> *authorizedKeys = nil;

    if (history && history.count > 0) {
        for (PLCOperation *prevOp in history) {
            authorizedKeys = prevOp.data[@"rotationKeys"];
            lastHash = [CryptoUtils hexStringFromData:[self hashForOperationData:prevOp.data]];
        }
    }

    if (!op.prev && lastHash) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unexpected genesis operation in middle of history"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }
    if (op.prev && [op.prev isKindOfClass:[NSString class]]) {
        NSLog(@"[PLC AUDITOR] Checking prev hash: %@ vs last: %@", op.prev, lastHash);
        if (![op.prev isEqualToString:lastHash]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Prev hash mismatch. Expected %@, got %@", lastHash, op.prev]}];
            }
            [[PLCMetrics sharedMetrics] recordVerificationFailure];
            return NO;
        }
    }

    if (!authorizedKeys) {
        authorizedKeys = op.data[@"rotationKeys"];
    }

    BOOL sigOk = NO;
    NSData *opDataHash = [self hashForOperationData:op.data];
    NSData *sigData = [self dataFromSignatureString:op.sig];
    
    NSLog(@"[PLC AUDITOR] Auditing DID %@. Hash: %@, Sig: %lu bytes", 
                 op.did, [CryptoUtils hexStringFromData:opDataHash], (unsigned long)sigData.length);

    for (NSString *keyString in authorizedKeys) {
        NSData *pubKey = [self dataFromKeyString:keyString];
        NSData *normalizedKey = [[Secp256k1 shared] normalizedPublicKey:pubKey error:nil];
        NSLog(@"[PLC AUDITOR] Checking key: %@. Parsed: %lu, Normalized: %lu", 
                     keyString, (unsigned long)pubKey.length, (unsigned long)normalizedKey.length);
        if (normalizedKey && [[Secp256k1 shared] verifySignature:sigData forHash:opDataHash withPublicKey:normalizedKey error:nil]) {
            sigOk = YES;
            break;
        }
    }

    if (!sigOk) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signature verification failed"}];
        }
        [[PLCMetrics sharedMetrics] recordVerificationFailure];
        return NO;
    }

    [[PLCMetrics sharedMetrics] recordVerificationSuccess];
    NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:startTime] * 1000;
    [[PLCMetrics sharedMetrics] recordResolutionLatency:latency];
    
    return YES;
}

- (NSData *)hashForOperationData:(NSDictionary *)data {
    NSError *error = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:data error:&error];
    if (!cbor) {
        return nil;
    }
    NSLog(@"[PLC AUDITOR] CBOR Data (%lu bytes): %@", (unsigned long)cbor.length, [CryptoUtils hexStringFromData:cbor]);
    return [CryptoUtils sha256:cbor];
}

- (NSData *)dataFromSignatureString:(NSString *)sig {
    if (!sig || ![sig isKindOfClass:[NSString class]]) return nil;
    // Try base64 first
    NSData *data = [[NSData alloc] initWithBase64EncodedString:sig options:0];
    if (data && (data.length == 64 || data.length == 65)) {
        return data;
    }
    // Fallback to hex
    if (sig.length == 128 || sig.length == 130) {
        return [self dataFromHexString:sig];
    }
    return data ?: [self dataFromHexString:sig];
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

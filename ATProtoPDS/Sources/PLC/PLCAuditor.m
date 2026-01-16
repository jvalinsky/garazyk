#import "PLC/PLCAuditor.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "Core/ATProtoCBORSerialization.h"

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
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did error:error];
    if (!history || history.count == 0) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty history"}];
        }
        return NO;
    }

    NSString *lastHash = nil;
    NSArray<NSString *> *authorizedKeys = nil;

    for (PLCOperation *op in history) {
        // 1. Verify prev hash
        if (!op.prev && lastHash) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected genesis operation in middle of history"}];
            }
            return NO;
        }
        if (op.prev && ![op.prev isEqualToString:lastHash]) {
            if (error) {
                *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Prev hash mismatch. Expected %@, got %@", lastHash, op.prev]}];
            }
            return NO;
        }

        // 2. Determine authorized keys
        if (!authorizedKeys) {
            // Genesis operation: authorized keys are the ones in the operation itself
            authorizedKeys = op.data[@"rotationKeys"];
        }

        // 3. Verify signature
        BOOL sigOk = NO;
        NSData *opDataHash = [self hashForOperationData:op.data];
        NSData *sigData = [self dataFromHexString:op.sig];

        for (NSString *keyHex in authorizedKeys) {
            NSData *pubKey = [self dataFromHexString:keyHex];
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
            return NO;
        }

        // 4. Update state
        authorizedKeys = op.data[@"rotationKeys"];
        lastHash = [CryptoUtils hexStringFromData:opDataHash];
    }

    return YES;
}

- (NSData *)hashForOperationData:(NSDictionary *)data {
    NSError *error = nil;
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:data error:&error];
    if (!cbor) {
        return nil;
    }
    return [CryptoUtils sha256:cbor];
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

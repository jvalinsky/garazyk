#import "DIDKey.h"
#import "Identity/DIDKeyEncoder.h"
#import "Auth/Secp256k1.h"
#import <CommonCrypto/CommonDigest.h>

static const uint8_t kMulticodecSecp256k1PublicKey = 0xe7;
static const uint8_t kMulticodecSecp256k1PrivateKey = 0x02;
static const uint8_t kMultibaseBase58BTC = 'z';

@implementation DIDKey

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (nullable instancetype)parse:(NSString *)didKeyString error:(NSError **)error {
    if (!didKeyString || didKeyString.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID key string cannot be empty"}];
        }
        return nil;
    }

    NSString *prefix = @"did:key:";
    if (![didKeyString hasPrefix:prefix]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID key must start with 'did:key:'"}];
        }
        return nil;
    }

    NSString *encoded = [didKeyString substringFromIndex:prefix.length];
    if (encoded.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID key encoded portion is empty"}];
        }
        return nil;
    }

    unichar multibasePrefix = [encoded characterAtIndex:0];
    if (multibasePrefix != kMultibaseBase58BTC) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidMultibase
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID key must use base58btc encoding (z prefix)"}];
        }
        return nil;
    }

    NSString *multicodecData = [encoded substringFromIndex:1];
    NSData *decodedData = [self base58Decode:multicodecData];
    if (!decodedData || decodedData.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidMultibase
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode base58btc data"}];
        }
        return nil;
    }

    if (decodedData.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Decoded data too short for multicodec"}];
        }
        return nil;
    }

    uint8_t multicodec = ((const uint8_t *)decodedData.bytes)[0];
    NSData *keyData = [decodedData subdataWithRange:NSMakeRange(1, decodedData.length - 1)];

    switch (multicodec) {
        case kMulticodecSecp256k1PublicKey:
            if (keyData.length != 33) {
                if (error) {
                    *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                                 code:DIDKeyErrorUnsupportedKeyType
                                             userInfo:@{NSLocalizedDescriptionKey: @"secp256k1 public key must be 33 bytes (compressed)"}];
                }
                return nil;
            }
            return [[DIDKey alloc] initWithPublicKeyData:keyData didKeyString:didKeyString];

        case kMulticodecSecp256k1PrivateKey:
            if (keyData.length != 32) {
                if (error) {
                    *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                                 code:DIDKeyErrorUnsupportedKeyType
                                             userInfo:@{NSLocalizedDescriptionKey: @"secp256k1 private key must be 32 bytes"}];
                }
                return nil;
            }
            return [[DIDKey alloc] initWithPublicKeyData:nil privateKeyData:keyData didKeyString:didKeyString];

        default:
            if (error) {
                *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                             code:DIDKeyErrorUnsupportedKeyType
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported multicodec: 0x%02x", multicodec]}];
            }
            return nil;
    }
}

+ (instancetype)generateSecp256k1 {
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:&error];
    if (!keyPair) {
        NSLog(@"Failed to generate secp256k1 key pair: %@", error);
        return nil;
    }

    NSData *privateKey = keyPair.privateKey;
    NSData *publicKey = keyPair.compressedPublicKey;

    NSMutableData *multicodecData = [NSMutableData data];
    uint8_t multicodec = kMulticodecSecp256k1PrivateKey;
    [multicodecData appendBytes:&multicodec length:1];
    [multicodecData appendData:privateKey];

    NSString *encoded = [self base58Encode:multicodecData];
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", encoded];

    return [[DIDKey alloc] initWithPublicKeyData:publicKey
                                    privateKeyData:privateKey
                                    didKeyString:didKey];
}

- (instancetype)initWithPublicKeyData:(NSData *)publicKeyData
                         didKeyString:(NSString *)didKeyString {
    return [self initWithPublicKeyData:publicKeyData privateKeyData:nil didKeyString:didKeyString];
}

- (instancetype)initWithPublicKeyData:(NSData *)publicKeyData
                        privateKeyData:(NSData *)privateKeyData
                         didKeyString:(NSString *)didKeyString {
    self = [super init];
    if (self) {
        _didKey = [didKeyString copy];
        _publicKeyData = [publicKeyData copy];
        _privateKeyData = [privateKeyData copy];
    }
    return self;
}

- (BOOL)isPublicKey {
    return self.privateKeyData == nil;
}

- (NSString *)fingerprint {
    if (!self.publicKeyData) {
        return @"";
    }

    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(self.publicKeyData.bytes, (CC_LONG)self.publicKeyData.length, hash);

    NSMutableString *fp = [NSMutableString stringWithString:@"z"];
    for (int i = 0; i < 8; i++) {
        [fp appendFormat:@"%02x", hash[i]];
    }
    return [fp copy];
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    if (!self.privateKeyData) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot sign: no private key available"}];
        }
        return nil;
    }

    NSData *hash = [self hashForSigning:data];
    return [[Secp256k1 shared] signHash:hash withPrivateKey:self.privateKeyData error:error];
}

- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error {
    if (!self.publicKeyData) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorVerificationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot verify: no public key available"}];
        }
        return NO;
    }

    NSData *hash = [self hashForSigning:data];
    return [[Secp256k1 shared] verifySignature:signature forHash:hash withPublicKey:self.publicKeyData error:error];
}

- (NSData *)hashForSigning:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Base58 BTC

+ (NSString *)base58Encode:(NSData *)data {
    static const char *alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

    if (data.length == 0) {
        return @"";
    }

    const uint8_t *input = data.bytes;
    NSUInteger inputLength = data.length;

    NSUInteger zeroCount = 0;
    while (zeroCount < inputLength && input[zeroCount] == 0) {
        zeroCount++;
    }

    NSMutableData *result = [NSMutableData dataWithCapacity:inputLength * 138 / 100 + 1];
    uint8_t *resultBytes = result.mutableBytes;
    NSUInteger resultLength = 1;

    resultBytes[0] = 0;

    for (NSUInteger i = zeroCount; i < inputLength; i++) {
        uint16_t carry = input[i];
        for (NSUInteger j = 0; j < resultLength; j++) {
            uint32_t digit = (uint32_t)(resultBytes[j] * 256 + carry);
            resultBytes[j] = digit % 58;
            carry = digit / 58;
        }
        while (carry > 0) {
            resultBytes[resultLength++] = carry % 58;
            carry /= 58;
        }
    }

    NSMutableString *string = [NSMutableString stringWithCapacity:zeroCount + resultLength];

    NSUInteger resultIndex = resultLength - 1;
    while (resultIndex > 0 && resultBytes[resultIndex] == 0) {
        resultIndex--;
    }

    for (NSUInteger i = resultIndex + 1; i > 0; i--) {
        [string appendFormat:@"%c", alphabet[resultBytes[i - 1]]];
    }

    for (NSUInteger i = 0; i < zeroCount; i++) {
        [string insertString:@"1" atIndex:0];
    }

    return [string copy];
}

+ (NSData *)base58Decode:(NSString *)string {
    static const int8_t alphabetMap[128] = {
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
        -1,  0,  1,  2,  3,  4,  5,  6,  7,  8, -1, -1, -1, -1, -1, -1,
        -1,  9, 10, 11, 12, 13, 14, 15, 16, -1, 17, 18, 19, -1, 20, 21,
        22, 23, 24, 25, 26, 27, -1, -1, -1, -1, -1, -1, 28, 29, 30, 31,
        -1, -1, -1, -1, -1, -1, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
        42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1, -1,
    };

    if (string.length == 0) {
        return nil;
    }

    const char *input = [string UTF8String];
    NSUInteger inputLength = strlen(input);

    NSUInteger zeroCount = 0;
    while (zeroCount < inputLength && input[zeroCount] == '1') {
        zeroCount++;
    }

    NSMutableData *result = [NSMutableData dataWithCapacity:inputLength];
    uint8_t *resultBytes = result.mutableBytes;
    NSUInteger resultLength = 1;

    resultBytes[0] = 0;

    for (NSUInteger i = zeroCount; i < inputLength; i++) {
        int8_t val = alphabetMap[(uint8_t)input[i]];
        if (val < 0) {
            return nil;
        }
        uint32_t carry = val;
        for (NSUInteger j = 0; j < resultLength; j++) {
            uint32_t digit = (uint32_t)(resultBytes[j] * 58 + carry);
            resultBytes[j] = digit % 256;
            carry = digit / 256;
        }
        while (carry > 0) {
            resultBytes[resultLength++] = carry % 256;
            carry /= 256;
        }
    }

    NSUInteger resultIndex = resultLength - 1;
    while (resultIndex > 0 && resultBytes[resultIndex] == 0) {
        resultIndex--;
    }

    NSMutableData *finalResult = [NSMutableData dataWithCapacity:zeroCount + resultIndex + 1];
    for (NSUInteger i = 0; i < zeroCount; i++) {
        uint8_t zero = 0;
        [finalResult appendBytes:&zero length:1];
    }

    for (NSInteger i = resultIndex; i >= 0; i--) {
        [finalResult appendBytes:&resultBytes[i] length:1];
    }

    return [finalResult copy];
}

#pragma mark - NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.didKey forKey:@"didKey"];
    [coder encodeObject:self.publicKeyData forKey:@"publicKeyData"];
    [coder encodeObject:self.privateKeyData forKey:@"privateKeyData"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSString *didKey = [coder decodeObjectOfClass:[NSString class] forKey:@"didKey"];
    NSData *publicKeyData = [coder decodeObjectOfClass:[NSData class] forKey:@"publicKeyData"];
    NSData *privateKeyData = [coder decodeObjectOfClass:[NSData class] forKey:@"privateKeyData"];

    if (!didKey) {
        return nil;
    }

    return [self initWithPublicKeyData:publicKeyData privateKeyData:privateKeyData didKeyString:didKey];
}

@end

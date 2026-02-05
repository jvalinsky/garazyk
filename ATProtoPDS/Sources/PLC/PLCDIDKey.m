#import "PLCDIDKey.h"
#import "Core/CID.h"

static NSString *const PLCDIDKeyErrorDomain = @"PLCDIDKeyErrorDomain";

static const uint64_t kMulticodecSecp256k1Pub = 0xE7;
static const uint64_t kMulticodecP256Pub = 0x1200;

static NSUInteger PLCReadVarint(const uint8_t *bytes, NSUInteger maxLength, uint64_t *value) {
    if (bytes == NULL || value == NULL || maxLength == 0) {
        return 0;
    }

    uint64_t result = 0;
    NSUInteger shift = 0;
    for (NSUInteger i = 0; i < maxLength && i < 10; i++) {
        uint8_t byte = bytes[i];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        if ((byte & 0x80) == 0) {
            *value = result;
            return i + 1;
        }
        shift += 7;
    }

    return 0;
}

@interface PLCDIDKey ()
@property (nonatomic, assign, readwrite) PLCDIDKeyType type;
@property (nonatomic, copy, readwrite) NSData *publicKeyBytes;
@end

@implementation PLCDIDKey

+ (nullable instancetype)parseFromString:(NSString *)didKey error:(NSError **)error {
    if (![didKey hasPrefix:@"did:key:"]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid prefix"}];
        }
        return nil;
    }

    NSString *multibase = [didKey substringFromIndex:@"did:key:".length];
    if (multibase.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:key payload"}];
        }
        return nil;
    }

    unichar multibasePrefix = [multibase characterAtIndex:0];
    if (multibasePrefix != 'z') {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported multibase prefix (expected 'z' base58btc)"}];
        }
        return nil;
    }

    NSString *base58Payload = [multibase substringFromIndex:1];
    NSData *decoded = [CID base58btcDecode:base58Payload];
    if (!decoded || decoded.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid base58btc payload"}];
        }
        return nil;
    }

    const uint8_t *bytes = decoded.bytes;
    uint64_t multicodec = 0;
    NSUInteger prefixSize = PLCReadVarint(bytes, decoded.length, &multicodec);
    if (prefixSize == 0 || prefixSize >= decoded.length) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid multicodec prefix"}];
        }
        return nil;
    }

    NSData *publicKeyBytes = [decoded subdataWithRange:NSMakeRange(prefixSize, decoded.length - prefixSize)];

    PLCDIDKeyType type;
    if (multicodec == kMulticodecSecp256k1Pub) {
        type = PLCDIDKeyTypeSecp256k1;
    } else if (multicodec == kMulticodecP256Pub) {
        type = PLCDIDKeyTypeP256;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported multicodec: 0x%llx", multicodec]}];
        }
        return nil;
    }

    if (publicKeyBytes.length != 33) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unexpected public key length (expected 33-byte compressed key)"}];
        }
        return nil;
    }

    const uint8_t first = ((const uint8_t *)publicKeyBytes.bytes)[0];
    if (first != 0x02 && first != 0x03) {
        if (error) {
            *error = [NSError errorWithDomain:PLCDIDKeyErrorDomain
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid compressed public key prefix"}];
        }
        return nil;
    }

    PLCDIDKey *key = [[PLCDIDKey alloc] init];
    key.type = type;
    key.publicKeyBytes = publicKeyBytes;
    return key;
}

+ (BOOL)isValidDidKeyString:(NSString *)didKey error:(NSError **)error {
    return [self parseFromString:didKey error:error] != nil;
}

@end

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoPFP.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

NSString * const ATProtoPFPErrorDomain = @"com.atproto.pfp";

static const NSUInteger kPFPInlineHashLength = 32;
static const NSUInteger kPFPCIDLength = 36;

static NSString *PFPBase32Encode(NSData *data);

static NSError *PFPError(ATProtoPFPErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoPFPErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void PFPSetError(NSError **error, ATProtoPFPErrorCode code, NSString *message) {
    if (error) *error = PFPError(code, message);
}

static BOOL PFPReadVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *index,
                          uint64_t *value, NSError **error) {
    uint64_t result = 0;
    NSUInteger shift = 0;
    NSUInteger start = *index;
    for (NSUInteger i = 0; i < 10; i++) {
        if (*index >= length) {
            PFPSetError(error, ATProtoPFPErrorTruncatedData, @"PFP varint is truncated");
            return NO;
        }
        uint8_t byte = bytes[(*index)++];
        uint64_t payload = byte & 0x7F;
        if (shift == 63 && payload > 1) {
            PFPSetError(error, ATProtoPFPErrorInvalidLength, @"PFP varint overflows uint64");
            return NO;
        }
        result |= payload << shift;
        if ((byte & 0x80) == 0) {
            NSUInteger encodedLength = *index - start;
            if (encodedLength > 1 && payload == 0) {
                PFPSetError(error, ATProtoPFPErrorNonCanonicalVarint,
                            @"PFP varint uses a non-minimal encoding");
                return NO;
            }
            *value = result;
            return YES;
        }
        shift += 7;
    }
    PFPSetError(error, ATProtoPFPErrorInvalidLength, @"PFP varint is too long");
    return NO;
}

static BOOL PFPAppendVarint(uint64_t value, NSMutableData *output) {
    do {
        uint8_t byte = (uint8_t)(value & 0x7F);
        value >>= 7;
        if (value != 0) byte |= 0x80;
        [output appendBytes:&byte length:1];
    } while (value != 0);
    return YES;
}

static int PFPBase32Value(unichar character) {
    if (character >= 'a' && character <= 'z') return (int)(character - 'a');
    if (character >= '2' && character <= '7') return (int)(character - '2' + 26);
    return -1;
}

static NSData *PFPBase32DecodeStrict(NSString *string, NSError **error) {
    if (![string isKindOfClass:[NSString class]] || string.length == 0) {
        PFPSetError(error, ATProtoPFPErrorInvalidBase32, @"PFP base32 payload is empty");
        return nil;
    }
    NSMutableData *result = [NSMutableData dataWithCapacity:string.length * 5 / 8];
    uint32_t buffer = 0;
    NSUInteger bits = 0;
    for (NSUInteger i = 0; i < string.length; i++) {
        int value = PFPBase32Value([string characterAtIndex:i]);
        if (value < 0) {
            PFPSetError(error, ATProtoPFPErrorInvalidBase32,
                        @"PFP base32 must use lowercase RFC4648 alphabet without padding");
            return nil;
        }
        buffer = (buffer << 5) | (uint32_t)value;
        bits += 5;
        while (bits >= 8) {
            bits -= 8;
            uint8_t byte = (uint8_t)((buffer >> bits) & 0xFF);
            [result appendBytes:&byte length:1];
        }
        buffer = bits == 0 ? 0 : buffer & ((1U << bits) - 1U);
    }
    if (bits > 0 && (buffer & ((1U << bits) - 1U)) != 0) {
        PFPSetError(error, ATProtoPFPErrorInvalidBase32,
                    @"PFP base32 has non-zero trailing padding bits");
        return nil;
    }
    return result;
}

static NSString *PFPBase32Encode(NSData *data) {
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";
    const uint8_t *bytes = data.bytes;
    NSMutableString *result = [NSMutableString stringWithCapacity:(data.length * 8 + 4) / 5];
    uint32_t buffer = 0;
    NSUInteger bits = 0;
    for (NSUInteger i = 0; i < data.length; i++) {
        buffer = (buffer << 8) | bytes[i];
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            [result appendFormat:@"%c", alphabet[(buffer >> bits) & 0x1F]];
        }
        buffer = bits == 0 ? 0 : buffer & ((1U << bits) - 1U);
    }
    if (bits > 0) {
        buffer <<= 5 - bits;
        [result appendFormat:@"%c", alphabet[buffer & 0x1F]];
    }
    return result;
}

static NSUInteger PFPExpectedLength(ATProtoPFPAlgorithm algorithm) {
    return algorithm == ATProtoPFPAlgorithmPDQ ? kPFPInlineHashLength : kPFPCIDLength;
}

@implementation ATProtoPFP

+ (nullable instancetype)pfpFromBytes:(NSData *)data error:(NSError **)error {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        PFPSetError(error, ATProtoPFPErrorInvalidType, @"PFP bytes must be non-empty NSData");
        return nil;
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger index = 0;
    uint64_t algorithmValue = 0;
    uint64_t lengthValue = 0;
    if (!PFPReadVarint(bytes, data.length, &index, &algorithmValue, error) ||
        !PFPReadVarint(bytes, data.length, &index, &lengthValue, error)) return nil;
    if (algorithmValue == 0 ||
        (algorithmValue != ATProtoPFPAlgorithmPDQ && algorithmValue != ATProtoPFPAlgorithmTMKPDQF)) {
        PFPSetError(error, ATProtoPFPErrorUnsupportedAlgorithm, @"PFP algorithm is not registered");
        return nil;
    }
    ATProtoPFPAlgorithm algorithm = (ATProtoPFPAlgorithm)algorithmValue;
    if (lengthValue != PFPExpectedLength(algorithm)) {
        PFPSetError(error, ATProtoPFPErrorInvalidLength, @"PFP data length does not match its algorithm");
        return nil;
    }
    if (lengthValue > data.length - index) {
        PFPSetError(error, ATProtoPFPErrorTruncatedData, @"PFP data is truncated");
        return nil;
    }
    NSData *payload = [data subdataWithRange:NSMakeRange(index, (NSUInteger)lengthValue)];
    index += (NSUInteger)lengthValue;
    if (index != data.length) {
        PFPSetError(error, ATProtoPFPErrorTrailingData, @"PFP contains trailing bytes");
        return nil;
    }

    ATProtoCID *dataCID = nil;
    if (algorithm == ATProtoPFPAlgorithmTMKPDQF) {
        dataCID = [ATProtoCID daslCIDFromBytes:payload profile:ATProtoDASLCIDProfileBase];
        if (!dataCID) {
            PFPSetError(error, ATProtoPFPErrorInvalidCID,
                        @"TMK+PDQF PFP data must be a strict base DASL CID");
            return nil;
        }
    }

    ATProtoPFP *pfp = [[self alloc] init];
    pfp->_algorithm = algorithm;
    pfp->_data = [payload copy];
    pfp->_dataCID = dataCID;
    return pfp;
}

+ (nullable instancetype)pfpFromString:(NSString *)string error:(NSError **)error {
    if (![string isKindOfClass:[NSString class]] || string.length < 2 ||
        [string characterAtIndex:0] != 'p') {
        PFPSetError(error, ATProtoPFPErrorInvalidPrefix, @"PFP string must start with lowercase p");
        return nil;
    }
    NSString *payload = [string substringFromIndex:1];
    NSData *bytes = PFPBase32DecodeStrict(payload, error);
    if (!bytes) return nil;
    if (![PFPBase32Encode(bytes) isEqualToString:payload]) {
        PFPSetError(error, ATProtoPFPErrorInvalidBase32,
                    @"PFP base32 is not the canonical encoding of its bytes");
        return nil;
    }
    return [self pfpFromBytes:bytes error:error];
}

+ (nullable instancetype)pfpFromJSONObject:(id)object error:(NSError **)error {
    if (![object isKindOfClass:[NSDictionary class]] || [(NSDictionary *)object count] != 1 ||
        ![object[@"__pfp"] isKindOfClass:[NSString class]]) {
        PFPSetError(error, ATProtoPFPErrorInvalidType,
                    @"PFP JSON pseudo-type must be exactly {__pfp: string}");
        return nil;
    }
    return [self pfpFromString:object[@"__pfp"] error:error];
}

- (NSData *)bytes {
    NSMutableData *result = [NSMutableData data];
    PFPAppendVarint(self.algorithm, result);
    PFPAppendVarint(self.data.length, result);
    [result appendData:self.data];
    return result;
}

- (NSString *)stringValue {
    return [@"p" stringByAppendingString:PFPBase32Encode(self.bytes)];
}

- (NSDictionary<NSString *, NSString *> *)JSONObjectRepresentation {
    return @{@"__pfp": self.stringValue};
}

+ (NSUInteger)recommendedPDQMatchDistance {
    return 31;
}

+ (BOOL)hammingDistanceBetweenPDQ:(ATProtoPFP *)left
                            andPDQ:(ATProtoPFP *)right
                          distance:(NSUInteger *)outDistance
                             error:(NSError **)error {
    if (![left isKindOfClass:[ATProtoPFP class]] ||
        ![right isKindOfClass:[ATProtoPFP class]] ||
        left.algorithm != ATProtoPFPAlgorithmPDQ ||
        right.algorithm != ATProtoPFPAlgorithmPDQ ||
        left.data.length != kPFPInlineHashLength ||
        right.data.length != kPFPInlineHashLength) {
        PFPSetError(error, ATProtoPFPErrorUnsupportedAlgorithm,
                    @"PDQ Hamming distance requires two PDQ PFPs with 32-byte hashes");
        return NO;
    }
    const uint8_t *a = left.data.bytes;
    const uint8_t *b = right.data.bytes;
    NSUInteger distance = 0;
    for (NSUInteger i = 0; i < kPFPInlineHashLength; i++) {
        uint8_t x = (uint8_t)(a[i] ^ b[i]);
#if defined(__GNUC__) || defined(__clang__)
        distance += (NSUInteger)__builtin_popcount(x);
#else
        while (x) {
            distance += x & 1U;
            x >>= 1;
        }
#endif
    }
    if (outDistance) *outDistance = distance;
    return YES;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[ATProtoPFP class]] &&
           self.algorithm == ((ATProtoPFP *)object).algorithm &&
           [self.data isEqualToData:((ATProtoPFP *)object).data];
}

- (NSUInteger)hash {
    return (NSUInteger)self.algorithm ^ self.data.hash;
}

- (NSString *)description {
    return self.stringValue;
}

@end

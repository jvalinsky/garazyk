// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/CID+DASL.h"

const uint8_t ATProtoDASLCodecRaw = 0x55;
const uint8_t ATProtoDASLCodecDRISL = 0x71;
const uint8_t ATProtoDASLMultihashSHA256 = 0x12;
const uint8_t ATProtoDASLMultihashBLAKE3 = 0x1e;

// 0x01 version + 1 codec + 1 multihash code + 1 digest length + 32 digest.
const NSUInteger ATProtoDASLCIDByteLength = 36;
// ceil(36 * 8 / 5) = 58 base32 characters, plus the `b` multibase prefix.
const NSUInteger ATProtoDASLCIDStringLength = 59;

static const uint8_t kDASLCIDVersion = 0x01;
static const uint8_t kDASLDigestLength = 0x20;

/// Lowercase RFC 4648 base32, matching the alphabet ATProtoCID.m encodes with.
static const char kDASLBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

/// Returns the alphabet index of `c`, or -1 if it is not a base32 character.
/// Deliberately case-sensitive: uppercase decodes to the same bytes but is a
/// second spelling of the same ATProtoCID, which the spec does not allow.
static int DASLBase32Index(unichar c) {
    if (c >= 'a' && c <= 'z') return (int)(c - 'a');
    if (c >= '2' && c <= '7') return (int)(c - '2' + 26);
    return -1;
}

static BOOL DASLProfileAllowsMultihash(uint8_t code, ATProtoDASLCIDProfile profile) {
    if (code == ATProtoDASLMultihashSHA256) {
        return YES;
    }
    return profile == ATProtoDASLCIDProfileBig && code == ATProtoDASLMultihashBLAKE3;
}

@implementation ATProtoCID (DASL)

+ (nullable ATProtoCID *)daslCIDFromString:(NSString *)string {
    return [self daslCIDFromString:string profile:ATProtoDASLCIDProfileBase];
}

+ (nullable ATProtoCID *)daslCIDFromString:(NSString *)string
                            profile:(ATProtoDASLCIDProfile)profile {
    if (![string isKindOfClass:[NSString class]] ||
        string.length != ATProtoDASLCIDStringLength) {
        return nil;
    }
    if ([string characterAtIndex:0] != 'b') {
        return nil;
    }

    uint8_t decoded[ATProtoDASLCIDByteLength];
    NSUInteger outLength = 0;
    uint32_t buffer = 0;
    int bitsLeft = 0;

    for (NSUInteger i = 1; i < string.length; i++) {
        int index = DASLBase32Index([string characterAtIndex:i]);
        if (index < 0) {
            return nil;
        }
        buffer = (buffer << 5) | (uint32_t)index;
        bitsLeft += 5;
        if (bitsLeft >= 8) {
            bitsLeft -= 8;
            if (outLength >= ATProtoDASLCIDByteLength) {
                return nil;
            }
            decoded[outLength++] = (uint8_t)((buffer >> bitsLeft) & 0xFF);
        }
    }

    if (outLength != ATProtoDASLCIDByteLength) {
        return nil;
    }

    // 58 characters carry 290 bits but a ATProtoCID is 288, so the last two bits are
    // padding and must be zero. A non-zero remainder decodes to the same bytes
    // yet re-encodes to a different final character — one ATProtoCID, two spellings.
    if (bitsLeft != 2 || (buffer & 0x03) != 0) {
        return nil;
    }

    return [self daslCIDFromBytes:[NSData dataWithBytes:decoded length:outLength]
                          profile:profile];
}

+ (nullable ATProtoCID *)daslCIDFromBytes:(NSData *)data {
    return [self daslCIDFromBytes:data profile:ATProtoDASLCIDProfileBase];
}

+ (nullable ATProtoCID *)daslCIDFromBytes:(NSData *)data
                           profile:(ATProtoDASLCIDProfile)profile {
    if (![data isKindOfClass:[NSData class]] ||
        data.length != ATProtoDASLCIDByteLength) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;

    // Byte equality, not varint parsing. Every field here is a single byte in
    // a conformant ATProtoCID, so refusing to run a varint decoder is what rejects
    // the padded spellings (0x81 0x00) that decode to the same numbers.
    if (bytes[0] != kDASLCIDVersion) {
        return nil;
    }
    if (bytes[1] != ATProtoDASLCodecRaw && bytes[1] != ATProtoDASLCodecDRISL) {
        return nil;
    }
    if (!DASLProfileAllowsMultihash(bytes[2], profile)) {
        return nil;
    }
    if (bytes[3] != kDASLDigestLength) {
        return nil;
    }

    NSData *multihash = [data subdataWithRange:NSMakeRange(2, ATProtoDASLCIDByteLength - 2)];
    return [ATProtoCID cidWithMultihash:multihash codec:bytes[1]];
}

- (BOOL)isDASLConformant {
    return [self isDASLConformantForProfile:ATProtoDASLCIDProfileBase];
}

- (BOOL)isDASLConformantForProfile:(ATProtoDASLCIDProfile)profile {
    if (self.version != 1) {
        return NO;
    }
    if (self.codec != ATProtoDASLCodecRaw && self.codec != ATProtoDASLCodecDRISL) {
        return NO;
    }
    NSData *multihash = self.multihash;
    if (multihash.length != ATProtoDASLCIDByteLength - 2) {
        return NO;
    }
    const uint8_t *bytes = multihash.bytes;
    return DASLProfileAllowsMultihash(bytes[0], profile) && bytes[1] == kDASLDigestLength;
}

@end

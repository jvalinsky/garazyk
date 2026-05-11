// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

static inline NSData *_Nullable PDSTestDataFromHexString(NSString *hex, NSUInteger expectedLength) {
    if (![hex isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *normalized = [[hex stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString];
    if (normalized.length != expectedLength * 2) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithCapacity:expectedLength];
    for (NSUInteger i = 0; i < normalized.length; i += 2) {
        unsigned int value = 0;
        NSString *byteString = [normalized substringWithRange:NSMakeRange(i, 2)];
        NSScanner *scanner = [NSScanner scannerWithString:byteString];
        if (![scanner scanHexInt:&value]) {
            return nil;
        }
        uint8_t byte = (uint8_t)(value & 0xFF);
        [data appendBytes:&byte length:1];
    }
    return data.length == expectedLength ? data : nil;
}

static inline SecKeyRef _Nullable PDSTestCreateFixedP256PrivateKey(NSError **error) CF_RETURNS_RETAINED {
    NSData *xData = PDSTestDataFromHexString(@"44073c1c6da8c2c9736c011ff13a2b3602a1d819e687582bdf87262ad1b12f50", 32);
    NSData *yData = PDSTestDataFromHexString(@"79720e75ce2eaae05079972dd065b2eb437d9af5c9a974d3ce186525494bdc3c", 32);
    NSData *dData = PDSTestDataFromHexString(@"8d12e99fb324f3c1bafed77fa91968a36c252590f0e55fef10f9bfb027b59504", 32);
    if (!xData || !yData || !dData) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSTestKeyFixtures"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode fixed P-256 key bytes"}];
        }
        return NULL;
    }

    NSMutableData *privateKeyData = [NSMutableData dataWithCapacity:97];
    uint8_t prefix = 0x04;
    [privateKeyData appendBytes:&prefix length:1];
    [privateKeyData appendData:xData];
    [privateKeyData appendData:yData];
    [privateKeyData appendData:dData];

    NSDictionary *attributes = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPrivate,
        (id)kSecAttrKeySizeInBits: @256
    };

    CFErrorRef keyErrorRef = NULL;
    SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData, (__bridge CFDictionaryRef)attributes, &keyErrorRef);
    if (privateKey == NULL && error) {
        *error = keyErrorRef ? CFBridgingRelease(keyErrorRef) : nil;
    } else if (keyErrorRef) {
        CFRelease(keyErrorRef);
    }
    return privateKey;
}

NS_ASSUME_NONNULL_END

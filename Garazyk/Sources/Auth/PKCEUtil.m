// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/PKCEUtil.h"
#import "Auth/CryptoUtils.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString * const kBase64URLAlphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

@implementation PKCEUtil

+ (NSString *)generateCodeVerifier {
    NSData *randomData = [CryptoUtils randomBytes:32];
    return [CryptoUtils base64URLEncode:randomData];
}

+ (NSString *)generateCodeChallengeWithVerifier:(NSString *)verifier {
    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    if (!verifierData) return nil;
    NSData *hashData = [CryptoUtils sha256:verifierData];
    return [CryptoUtils base64URLEncode:hashData];
}

+ (BOOL)verifyCodeChallenge:(NSString *)challenge withVerifier:(NSString *)verifier {
    NSString *expectedChallenge = [self generateCodeChallengeWithVerifier:verifier];
    return [challenge isEqualToString:expectedChallenge];
}

@end

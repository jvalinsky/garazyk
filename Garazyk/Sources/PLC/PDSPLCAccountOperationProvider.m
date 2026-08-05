// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPLCAccountOperationProvider.m

 @abstract PLC-owned account-operation provider used by PDSApplication.
 */

#import "PLC/PDSPLCAccountOperationProvider.h"
#import "PLC/PLCRotationKeyManager.h"
#import "PLC/PLCOperation.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Auth/Crypto/CryptoUtils.h"

@implementation PDSPLCAccountOperationProvider {
    PLCRotationKeyManager *_keyManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _keyManager = [PLCRotationKeyManager sharedManager];
    }
    return self;
}

- (nullable NSString *)rotationKeyDidKey {
    return _keyManager.rotationKeyDidKey;
}

- (BOOL)loadOrGenerateKeyWithError:(NSError **)error {
    return [_keyManager loadOrGenerateKeyWithError:error];
}

- (nullable NSDictionary *)signedOperationForUnsignedData:(NSDictionary *)unsignedData
                                                    error:(NSError **)error {
    if (![unsignedData isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.plc"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"PLC operation data must be a dictionary"}];
        }
        return nil;
    }

    NSData *unsignedCBOR = [[[ATProtoCBORSerialization alloc] initWithContentAddressed:NO]
                            encodeDataWithJSONObject:unsignedData
                            error:error];
    if (!unsignedCBOR) {
        return nil;
    }

    NSData *hash = [ATProtoCID rawSha256:unsignedCBOR];
    NSData *sig = nil;
    if (![_keyManager signHash:hash result:&sig error:error] || sig.length == 0) {
        return nil;
    }

    NSMutableDictionary *signedData = [unsignedData mutableCopy];
    signedData[@"sig"] = [ATProtoCryptoUtils base64URLEncode:sig];
    return [signedData copy];
}

- (nullable NSString *)didForSignedOperation:(NSDictionary *)signedOperation
                                       error:(NSError **)error {
    if (![signedOperation isKindOfClass:[NSDictionary class]] ||
        ![signedOperation[@"sig"] isKindOfClass:[NSString class]] ||
        [signedOperation[@"sig"] length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.plc"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"PLC DID derivation requires a signed operation"}];
        }
        return nil;
    }

    NSString *did = [PLCOperation calculateDIDForSignedOperation:signedOperation];
    if (did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.plc"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive did:plc from signed operation"}];
        }
        return nil;
    }
    return did;
}

@end

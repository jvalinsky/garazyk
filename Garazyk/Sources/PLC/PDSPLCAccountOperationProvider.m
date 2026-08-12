// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/PDSPLCAccountOperationProvider.h"
#import "PLC/PLCRotationKeyManager.h"
#import "PLC/PLCOperation.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/CID.h"

@interface PDSPLCAccountOperationProvider ()
@property (nonatomic, strong) ATProtoPLCRotationKeyManager *keyManager;
@end

@implementation PDSPLCAccountOperationProvider

- (instancetype)init {
    if ((self = [super init])) {
        _keyManager = [ATProtoPLCRotationKeyManager sharedManager];
    }
    return self;
}

- (NSString *)rotationKeyDidKey {
    return self.keyManager.rotationKeyDidKey;
}

- (BOOL)loadOrGenerateKeyWithError:(NSError **)error {
    return [self.keyManager loadOrGenerateKeyWithError:error];
}

- (NSDictionary *)signedOperationForUnsignedData:(NSDictionary *)unsignedData
                                            error:(NSError **)error {
    NSError *encodingError = nil;
    NSData *unsignedCBOR = [[[ATProtoCBORSerialization alloc] initWithContentAddressed:NO]
        encodeDataWithJSONObject:unsignedData error:&encodingError];
    if (!unsignedCBOR) {
        if (error) *error = encodingError;
        return nil;
    }

    NSData *hash = [ATProtoCID rawSha256:unsignedCBOR];
    NSData *signature = nil;
    if (![self.keyManager signHash:hash result:&signature error:error] || !signature) {
        return nil;
    }

    NSMutableDictionary *signedOperation = [unsignedData mutableCopy];
    signedOperation[@"sig"] = [ATProtoCryptoUtils base64URLEncode:signature];
    return [signedOperation copy];
}

- (NSString *)didForSignedOperation:(NSDictionary *)signedOperation
                               error:(NSError **)error {
    NSString *did = [ATProtoPLCOperation calculateDIDForSignedOperation:signedOperation];
    if (did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSPLCAccountOperationProvider"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive did:plc from signed operation"}];
        }
        return nil;
    }
    return did;
}

@end

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoIrohBlobHashMapping.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/ATProtoBao.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

NSErrorDomain const ATProtoIrohBlobHashMappingErrorDomain = @"com.atproto.iroh.hashmapping";

static NSError *IrohMapErr(ATProtoIrohBlobHashMappingErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoIrohBlobHashMappingErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ATProtoIrohBlobHashMapping

+ (nullable NSData *)irohBlobsHashFromGarazykCAVODCID:(ATProtoCID *)cid
                                                error:(NSError **)error {
    if (![cid isKindOfClass:[ATProtoCID class]]) {
        if (error) *error = IrohMapErr(ATProtoIrohBlobHashMappingErrorInvalidCID, @"CID required");
        return nil;
    }
    NSData *mh = cid.multihash;
    if (mh.length < 34 ||
        ((const uint8_t *)mh.bytes)[0] != ATProtoDASLMultihashBLAKE3 ||
        ((const uint8_t *)mh.bytes)[1] != 0x20) {
        if (error) {
            *error = IrohMapErr(ATProtoIrohBlobHashMappingErrorUnsupportedHash,
                                @"Garazyk CA/VOD iroh fetch requires BLAKE3 multihash");
        }
        return nil;
    }
    if (![cid isDASLConformantForProfile:ATProtoDASLCIDProfileBig]) {
        if (error) *error = IrohMapErr(ATProtoIrohBlobHashMappingErrorInvalidCID, @"Invalid Big DASL CID");
        return nil;
    }
    return [mh subdataWithRange:NSMakeRange(2, 32)];
}

+ (nullable NSData *)baoRootHashForObjectData:(NSData *)data {
    if (![data isKindOfClass:[NSData class]]) {
        return nil;
    }
    NSData *hash = [ATProtoBao hashForData:data];
    return hash.length == 32 ? hash : nil;
}

+ (BOOL)garazykCAVODCID:(ATProtoCID *)cid matchesObjectData:(NSData *)data {
    NSError *error = nil;
    NSData *digest = [self irohBlobsHashFromGarazykCAVODCID:cid error:&error];
    NSData *root = [self baoRootHashForObjectData:data];
    return digest.length == 32 && [digest isEqualToData:root];
}

@end

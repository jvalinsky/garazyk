// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoCAObjectStore.h"

#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Core/ATProtoBDASLVerifier.h"
#import "Core/ATProtoBao.h"
#import "Compat/PDSTypes.h"
#include "Security/Space/Vendor/BLAKE3/blake3.h"

NSErrorDomain const ATProtoCAObjectStoreErrorDomain = @"com.atproto.ca.objectstore";

static const char kOutboardMagic[4] = { 'G', 'Z', 'B', 'O' };
static const uint32_t kOutboardVersion = 1;

static NSError *CAStoreError(ATProtoCAObjectStoreErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoCAObjectStoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSData *ATProtoCAHashBLAKE3(NSData *data) {
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    if (data.length > 0) {
        blake3_hasher_update(&hasher, data.bytes, data.length);
    }
    uint8_t digest[BLAKE3_OUT_LEN];
    blake3_hasher_finalize(&hasher, digest, sizeof(digest));
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static NSData *ATProtoCAHashBLAKE3Bytes(const void *bytes, size_t length) {
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    if (length > 0) {
        blake3_hasher_update(&hasher, bytes, length);
    }
    uint8_t digest[BLAKE3_OUT_LEN];
    blake3_hasher_finalize(&hasher, digest, sizeof(digest));
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static void ATProtoCAAppendUInt32BE(NSMutableData *data, uint32_t value) {
    uint8_t b[4] = {
        (uint8_t)((value >> 24) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 8) & 0xff),
        (uint8_t)(value & 0xff),
    };
    [data appendBytes:b length:4];
}

static void ATProtoCAAppendUInt64BE(NSMutableData *data, uint64_t value) {
    uint8_t b[8];
    for (int i = 7; i >= 0; i--) {
        b[i] = (uint8_t)(value & 0xff);
        value >>= 8;
    }
    [data appendBytes:b length:8];
}

static BOOL ATProtoCAReadUInt32BE(const uint8_t *bytes, NSUInteger length, NSUInteger *offset, uint32_t *out) {
    if (*offset + 4 > length) return NO;
    *out = ((uint32_t)bytes[*offset] << 24) | ((uint32_t)bytes[*offset + 1] << 16) |
           ((uint32_t)bytes[*offset + 2] << 8) | (uint32_t)bytes[*offset + 3];
    *offset += 4;
    return YES;
}

static BOOL ATProtoCAReadUInt64BE(const uint8_t *bytes, NSUInteger length, NSUInteger *offset, uint64_t *out) {
    if (*offset + 8 > length) return NO;
    uint64_t value = 0;
    for (int i = 0; i < 8; i++) {
        value = (value << 8) | bytes[*offset + (NSUInteger)i];
    }
    *offset += 8;
    *out = value;
    return YES;
}

@interface ATProtoCAObjectStore ()
@property (nonatomic, copy, readwrite) NSString *rootDirectory;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@end

@implementation ATProtoCAObjectStore

- (nullable instancetype)initWithRootDirectory:(NSString *)rootDirectory
                                         error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    if (rootDirectory.length == 0) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"Root directory is required");
        return nil;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *objects = [rootDirectory stringByAppendingPathComponent:@"objects"];
    NSString *proofs = [rootDirectory stringByAppendingPathComponent:@"proofs"];
    NSError *ioError = nil;
    if (![fm createDirectoryAtPath:objects withIntermediateDirectories:YES attributes:nil error:&ioError] ||
        ![fm createDirectoryAtPath:proofs withIntermediateDirectories:YES attributes:nil error:&ioError]) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorIO, ioError.localizedDescription ?: @"Failed to create store directories");
        return nil;
    }
    _rootDirectory = [rootDirectory copy];
    _queue = dispatch_queue_create("blue.microcosm.ca.objectstore", DISPATCH_QUEUE_SERIAL);
    return self;
}

+ (nullable ATProtoCID *)cidForData:(NSData *)data
                            profile:(ATProtoCAObjectDigestProfile)profile
                              error:(NSError **)error {
    if (!data) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"Data is required");
        return nil;
    }
    if (profile == ATProtoCAObjectDigestProfileSHA256) {
        return [ATProtoCID sha256:data];
    }
    if (profile == ATProtoCAObjectDigestProfileBLAKE3) {
        NSData *digest = ATProtoCAHashBLAKE3(data);
        NSMutableData *multihash = [NSMutableData dataWithCapacity:34];
        uint8_t header[2] = { ATProtoDASLMultihashBLAKE3, 0x20 };
        [multihash appendBytes:header length:2];
        [multihash appendData:digest];
        return [ATProtoCID cidWithMultihash:multihash codec:ATProtoDASLCodecRaw];
    }
    if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"Unknown digest profile");
    return nil;
}

- (NSString *)objectPathForCID:(ATProtoCID *)cid {
    return [[self.rootDirectory stringByAppendingPathComponent:@"objects"]
            stringByAppendingPathComponent:cid.stringValue];
}

- (NSString *)proofPathForCID:(ATProtoCID *)cid {
    NSString *name = [cid.stringValue stringByAppendingString:@".bao"];
    return [[self.rootDirectory stringByAppendingPathComponent:@"proofs"]
            stringByAppendingPathComponent:name];
}

- (nullable NSData *)buildOutboardForData:(NSData *)data error:(NSError **)error {
    // Phase 9: wire-compatible Bao outboard (regenerable; does not change media CID).
    return [ATProtoBao outboardForData:data ?: [NSData data] error:error];
}

- (nullable NSArray<NSData *> *)parseOutboard:(NSData *)outboard
                                  totalLength:(NSUInteger *)totalLengthOut
                                    chunkSize:(NSUInteger *)chunkSizeOut
                                        error:(NSError **)error {
    if (outboard.length < 4 + 4 + 8 + 4 + 4) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Outboard too short");
        return nil;
    }
    const uint8_t *bytes = outboard.bytes;
    if (memcmp(bytes, kOutboardMagic, 4) != 0) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Bad outboard magic");
        return nil;
    }
    NSUInteger offset = 4;
    uint32_t version = 0;
    uint64_t totalLength = 0;
    uint32_t chunkSize = 0;
    uint32_t count = 0;
    if (!ATProtoCAReadUInt32BE(bytes, outboard.length, &offset, &version) ||
        !ATProtoCAReadUInt64BE(bytes, outboard.length, &offset, &totalLength) ||
        !ATProtoCAReadUInt32BE(bytes, outboard.length, &offset, &chunkSize) ||
        !ATProtoCAReadUInt32BE(bytes, outboard.length, &offset, &count)) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Truncated outboard header");
        return nil;
    }
    if (version != kOutboardVersion || chunkSize == 0 || count == 0) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Unsupported outboard header");
        return nil;
    }
    if (offset + (NSUInteger)count * 32 != outboard.length) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Outboard digest length mismatch");
        return nil;
    }
    NSMutableArray<NSData *> *digests = [NSMutableArray arrayWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        [digests addObject:[NSData dataWithBytes:bytes + offset + (NSUInteger)i * 32 length:32]];
    }
    if (totalLengthOut) *totalLengthOut = (NSUInteger)totalLength;
    if (chunkSizeOut) *chunkSizeOut = chunkSize;
    return digests;
}

- (nullable ATProtoCID *)putData:(NSData *)data
                     expectedCID:(nullable ATProtoCID *)expectedCID
                         profile:(ATProtoCAObjectDigestProfile)profile
                           error:(NSError **)error {
    __block ATProtoCID *result = nil;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        ATProtoCID *cid = [ATProtoCAObjectStore cidForData:data profile:profile error:&localError];
        if (!cid) return;
        if (expectedCID && ![expectedCID isEqual:cid]) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorCIDMismatch, @"Computed CID does not match expectedCID");
            return;
        }
        NSString *path = [self objectPathForCID:cid];
        if (![data writeToFile:path options:NSDataWritingAtomic error:&localError]) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorIO, localError.localizedDescription ?: @"Failed to write object");
            return;
        }
        if (profile == ATProtoCAObjectDigestProfileBLAKE3) {
            NSData *outboard = [self buildOutboardForData:data error:&localError];
            if (!outboard) return;
            NSString *proofPath = [self proofPathForCID:cid];
            if (![outboard writeToFile:proofPath options:NSDataWritingAtomic error:&localError]) {
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                localError = CAStoreError(ATProtoCAObjectStoreErrorIO, localError.localizedDescription ?: @"Failed to write proof");
                return;
            }
        }
        result = cid;
    });
    if (!result && error) *error = localError;
    return result;
}

- (nullable NSDictionary<NSString *, id> *)statCID:(ATProtoCID *)cid error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"CID is required");
        return nil;
    }
    __block NSDictionary *result = nil;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        NSString *path = [self objectPathForCID:cid];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&localError];
        if (!attrs) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorNotFound, @"Object not found");
            return;
        }
        BOOL hasProof = [[NSFileManager defaultManager] fileExistsAtPath:[self proofPathForCID:cid]];
        result = @{
            @"cid": cid,
            @"size": attrs[NSFileSize] ?: @0,
            @"hasProof": @(hasProof),
        };
    });
    if (!result && error) *error = localError;
    return result;
}

- (nullable NSData *)dataForCID:(ATProtoCID *)cid error:(NSError **)error {
    return [self dataForCID:cid offset:0 length:NSUIntegerMax error:error];
}

- (nullable NSData *)dataForCID:(ATProtoCID *)cid
                         offset:(NSUInteger)offset
                         length:(NSUInteger)length
                          error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"CID is required");
        return nil;
    }
    __block NSData *result = nil;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        NSString *path = [self objectPathForCID:cid];
        NSData *full = [NSData dataWithContentsOfFile:path options:0 error:&localError];
        if (!full) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorNotFound, @"Object not found");
            return;
        }
        if (offset > full.length) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorRange, @"Offset past end of object");
            return;
        }
        NSUInteger available = full.length - offset;
        NSUInteger take = length == NSUIntegerMax ? available : MIN(length, available);
        result = [full subdataWithRange:NSMakeRange(offset, take)];
    });
    if (!result && error) *error = localError;
    return result;
}

- (BOOL)deleteCID:(ATProtoCID *)cid error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"CID is required");
        return NO;
    }
    __block BOOL ok = NO;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        NSString *path = [self objectPathForCID:cid];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorNotFound, @"Object not found");
            return;
        }
        if (![fm removeItemAtPath:path error:&localError]) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorIO, localError.localizedDescription ?: @"Failed to delete object");
            return;
        }
        NSString *proofPath = [self proofPathForCID:cid];
        if ([fm fileExistsAtPath:proofPath]) {
            [fm removeItemAtPath:proofPath error:nil];
        }
        ok = YES;
    });
    if (!ok && error) *error = localError;
    return ok;
}

- (BOOL)generateProofForCID:(ATProtoCID *)cid error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"CID is required");
        return NO;
    }
    if (![cid isDASLConformantForProfile:ATProtoDASLCIDProfileBig] ||
        cid.multihash.length < 2 ||
        ((const uint8_t *)cid.multihash.bytes)[0] != ATProtoDASLMultihashBLAKE3) {
        // SHA-256 live objects do not need an outboard.
        return YES;
    }
    __block BOOL ok = NO;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        NSData *full = [NSData dataWithContentsOfFile:[self objectPathForCID:cid] options:0 error:&localError];
        if (!full) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorNotFound, @"Object not found");
            return;
        }
        NSData *outboard = [self buildOutboardForData:full error:&localError];
        if (!outboard) return;
        if (![outboard writeToFile:[self proofPathForCID:cid] options:NSDataWritingAtomic error:&localError]) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorIO, localError.localizedDescription ?: @"Failed to write proof");
            return;
        }
        ok = YES;
    });
    if (!ok && error) *error = localError;
    return ok;
}

- (BOOL)regenerateProofForCID:(ATProtoCID *)cid error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"CID is required");
        return NO;
    }
    if (![cid isDASLConformantForProfile:ATProtoDASLCIDProfileBig] ||
        cid.multihash.length < 2 ||
        ((const uint8_t *)cid.multihash.bytes)[0] != ATProtoDASLMultihashBLAKE3) {
        return YES;
    }
    __block BOOL ok = NO;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        NSString *proofPath = [self proofPathForCID:cid];
        [[NSFileManager defaultManager] removeItemAtPath:proofPath error:nil];
        NSData *full = [NSData dataWithContentsOfFile:[self objectPathForCID:cid] options:0 error:&localError];
        if (!full) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorNotFound, @"Object not found");
            return;
        }
        NSData *outboard = [self buildOutboardForData:full error:&localError];
        if (!outboard) return;
        if (![outboard writeToFile:proofPath options:NSDataWritingAtomic error:&localError]) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorIO, localError.localizedDescription ?: @"Failed to write proof");
            return;
        }
        ok = YES;
    });
    if (!ok && error) *error = localError;
    return ok;
}

- (nullable NSDictionary<NSString *, id> *)produceProofForCID:(ATProtoCID *)cid
                                                      offset:(NSUInteger)offset
                                                      length:(NSUInteger)length
                                                       error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidArgument, @"CID is required");
        return nil;
    }
    __block NSDictionary *result = nil;
    __block NSError *localError = nil;
    dispatch_sync(self.queue, ^{
        NSData *full = [NSData dataWithContentsOfFile:[self objectPathForCID:cid] options:0 error:&localError];
        if (!full) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorNotFound, @"Object not found");
            return;
        }
        if (offset > full.length) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorRange, @"Offset past end of object");
            return;
        }
        NSUInteger available = full.length - offset;
        NSUInteger take = MIN(length, available);

        NSData *outboard = [NSData dataWithContentsOfFile:[self proofPathForCID:cid] options:0 error:&localError];
        if (!outboard) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Proof outboard not found; generateProof first");
            return;
        }

        BOOL isGZBO = outboard.length >= 4 && memcmp(outboard.bytes, kOutboardMagic, 4) == 0;
        if (!isGZBO) {
            NSData *slice = [ATProtoBao sliceFromData:full
                                             outboard:outboard
                                               offset:offset
                                               length:take
                                                error:&localError];
            if (!slice) {
                localError = localError ?: CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Failed to extract Bao slice");
                return;
            }
            NSData *rangeData = take == 0 ? [NSData data] : [full subdataWithRange:NSMakeRange(offset, take)];
            NSData *rootHash = [ATProtoBao hashForData:full];
            result = @{
                @"cid": cid,
                @"offset": @(offset),
                @"length": @(take),
                @"totalLength": @(full.length),
                @"baoSlice": slice,
                @"rootHash": rootHash,
                @"rangeData": rangeData,
            };
            return;
        }

        NSData *rangeData = [full subdataWithRange:NSMakeRange(offset, take)];
        NSUInteger totalLength = 0;
        NSUInteger chunkSize = 0;
        NSArray<NSData *> *digests = [self parseOutboard:outboard
                                             totalLength:&totalLength
                                               chunkSize:&chunkSize
                                                   error:&localError];
        if (!digests) return;
        if (totalLength != full.length) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Outboard length does not match object");
            return;
        }
        NSUInteger first = offset / chunkSize;
        NSUInteger last = take == 0 ? first : (offset + take - 1) / chunkSize;
        if (last >= digests.count) {
            localError = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Range exceeds outboard chunks");
            return;
        }
        NSArray *sliceDigests = [digests subarrayWithRange:NSMakeRange(first, last - first + 1)];
        result = @{
            @"cid": cid,
            @"offset": @(offset),
            @"length": @(take),
            @"totalLength": @(totalLength),
            @"chunkSize": @(chunkSize),
            @"firstChunkIndex": @(first),
            @"chunkDigests": sliceDigests,
            @"allChunkDigests": digests,
            @"rangeData": rangeData,
        };
    });
    if (!result && error) *error = localError;
    return result;
}

+ (BOOL)verifyProof:(NSDictionary<NSString *, id> *)proof
      fullObjectData:(nullable NSData *)fullObjectData
               error:(NSError **)error {
    if (![proof isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Proof must be a dictionary");
        return NO;
    }

    NSData *baoSlice = proof[@"baoSlice"];
    NSData *rootHash = proof[@"rootHash"];
    NSNumber *offsetNum = proof[@"offset"];
    NSNumber *lengthNum = proof[@"length"];
    if ([baoSlice isKindOfClass:[NSData class]] && [rootHash isKindOfClass:[NSData class]] &&
        [offsetNum isKindOfClass:[NSNumber class]] && [lengthNum isKindOfClass:[NSNumber class]]) {
        NSError *baoError = nil;
        NSData *verified = [ATProtoBao verifiedContentFromSlice:baoSlice
                                                   expectedHash:rootHash
                                                         offset:offsetNum.unsignedIntegerValue
                                                         length:lengthNum.unsignedIntegerValue
                                                          error:&baoError];
        if (!verified) {
            if (error) *error = baoError ?: CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Bao slice verification failed");
            return NO;
        }
        NSData *rangeData = proof[@"rangeData"];
        if ([rangeData isKindOfClass:[NSData class]] && ![verified isEqualToData:rangeData]) {
            if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Verified range does not match rangeData");
            return NO;
        }
        ATProtoCID *cid = proof[@"cid"];
        if ([cid isKindOfClass:[ATProtoCID class]]) {
            NSData *mh = cid.multihash;
            if (mh.length >= 34) {
                NSData *digest = [mh subdataWithRange:NSMakeRange(2, 32)];
                if (![digest isEqualToData:rootHash]) {
                    if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorCIDMismatch, @"rootHash does not match CID");
                    return NO;
                }
            }
        }
        return YES;
    }

    ATProtoCID *cid = proof[@"cid"];
    NSData *rangeData = proof[@"rangeData"];
    NSNumber *totalNum = proof[@"totalLength"];
    NSNumber *chunkSizeNum = proof[@"chunkSize"];
    NSNumber *firstNum = proof[@"firstChunkIndex"];
    NSArray *sliceDigests = proof[@"chunkDigests"];
    NSArray *allDigests = proof[@"allChunkDigests"];
    if (![cid isKindOfClass:[ATProtoCID class]] || ![rangeData isKindOfClass:[NSData class]] ||
        ![offsetNum isKindOfClass:[NSNumber class]] || ![lengthNum isKindOfClass:[NSNumber class]] ||
        ![totalNum isKindOfClass:[NSNumber class]] || ![chunkSizeNum isKindOfClass:[NSNumber class]] ||
        ![firstNum isKindOfClass:[NSNumber class]] || ![sliceDigests isKindOfClass:[NSArray class]]) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Proof missing required fields");
        return NO;
    }
    NSUInteger offset = offsetNum.unsignedIntegerValue;
    NSUInteger length = lengthNum.unsignedIntegerValue;
    NSUInteger totalLength = totalNum.unsignedIntegerValue;
    NSUInteger chunkSize = chunkSizeNum.unsignedIntegerValue;
    NSUInteger first = firstNum.unsignedIntegerValue;
    if (rangeData.length != length) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"rangeData length mismatch");
        return NO;
    }
    if (chunkSize == 0) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Invalid chunk size");
        return NO;
    }

    for (NSUInteger i = 0; i < sliceDigests.count; i++) {
        NSUInteger chunkIndex = first + i;
        NSUInteger chunkStart = chunkIndex * chunkSize;
        NSUInteger chunkEnd = MIN(chunkStart + chunkSize, totalLength);
        NSUInteger overlapStart = MAX(chunkStart, offset);
        NSUInteger overlapEnd = MIN(chunkEnd, offset + length);
        if (overlapStart >= overlapEnd) continue;
        NSData *digest = sliceDigests[i];
        if (![digest isKindOfClass:[NSData class]] || digest.length != 32) {
            if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"Bad chunk digest");
            return NO;
        }
        if (fullObjectData) {
            if (fullObjectData.length != totalLength) {
                if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"fullObjectData length mismatch");
                return NO;
            }
            NSUInteger clen = chunkEnd - chunkStart;
            NSData *actual = ATProtoCAHashBLAKE3Bytes((const uint8_t *)fullObjectData.bytes + chunkStart, clen);
            if (![actual isEqualToData:digest]) {
                if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof,
                                                 [NSString stringWithFormat:@"Chunk %lu digest mismatch", (unsigned long)chunkIndex]);
                return NO;
            }
        } else if (overlapStart == chunkStart && overlapEnd == chunkEnd) {
            NSUInteger localStart = overlapStart - offset;
            NSData *actual = ATProtoCAHashBLAKE3Bytes((const uint8_t *)rangeData.bytes + localStart,
                                                      overlapEnd - overlapStart);
            if (![actual isEqualToData:digest]) {
                if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof,
                                                 [NSString stringWithFormat:@"Chunk %lu digest mismatch", (unsigned long)chunkIndex]);
                return NO;
            }
        } else {
            if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof,
                                             @"Partial chunk verification requires fullObjectData");
            return NO;
        }
    }

    NSData *objectBytes = fullObjectData;
    if (!objectBytes) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorInvalidProof,
                                         @"fullObjectData required to verify BLAKE3 content root");
        return NO;
    }
    ATProtoCID *computed = [self cidForData:objectBytes profile:ATProtoCAObjectDigestProfileBLAKE3 error:error];
    if (![computed isEqual:cid]) {
        if (error) *error = CAStoreError(ATProtoCAObjectStoreErrorCIDMismatch, @"Object does not match BLAKE3 CID root");
        return NO;
    }

    if ([allDigests isKindOfClass:[NSArray class]] && allDigests.count > 0) {
        NSError *vError = nil;
        ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc] initWithCID:cid
                                                                     chunkDigests:allDigests
                                                                      totalLength:totalLength
                                                                            error:&vError];
        if (!verifier || ![verifier appendData:objectBytes error:&vError] || ![verifier finalizeWithError:&vError]) {
            if (error) *error = vError ?: CAStoreError(ATProtoCAObjectStoreErrorInvalidProof, @"BDASL root verification failed");
            return NO;
        }
    }
    return YES;
}

@end

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoBDASLVerifier.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#include "Security/Space/Vendor/BLAKE3/blake3.h"

NSErrorDomain const ATProtoBDASLVerifierErrorDomain = @"com.atproto.bdasl.verifier";
const NSUInteger ATProtoBDASLChunkSize = 1024;
static const NSUInteger kBDASLDigestLength = 32;

static NSError *BDASLError(ATProtoBDASLVerifierErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoBDASLVerifierErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface ATProtoBDASLRootHasher : NSObject
- (void)updateWithData:(NSData *)data;
- (NSData *)finalDigest;
@end

@implementation ATProtoBDASLRootHasher {
    blake3_hasher _hasher;
    BOOL _finalized;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        blake3_hasher_init(&_hasher);
    }
    return self;
}

- (void)updateWithData:(NSData *)data {
    if (!_finalized && data.length > 0) {
        blake3_hasher_update(&_hasher, data.bytes, data.length);
    }
}

- (NSData *)finalDigest {
    if (_finalized) {
        return nil;
    }
    _finalized = YES;
    uint8_t digest[kBDASLDigestLength];
    blake3_hasher_finalize(&_hasher, digest, sizeof(digest));
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

@end

@interface ATProtoBDASLVerifier ()
@property (nonatomic, strong, readwrite) ATProtoCID *cid;
@property (nonatomic, copy) NSArray<NSData *> *chunkDigests;
@property (nonatomic, assign, readwrite) NSUInteger totalLength;
@property (nonatomic, assign, readwrite) NSUInteger bytesReceived;
@property (nonatomic, assign, readwrite) NSUInteger verifiedChunkCount;
@property (nonatomic, assign, readwrite, getter=isVerified) BOOL verified;
@property (nonatomic, strong) NSMutableData *pendingChunk;
@property (nonatomic, assign) NSUInteger nextChunkIndex;
@property (nonatomic, strong) ATProtoBDASLRootHasher *rootHasher;
@property (nonatomic, assign) BOOL failed;
@end

@implementation ATProtoBDASLVerifier

- (nullable instancetype)initWithCID:(ATProtoCID *)cid
                        chunkDigests:(NSArray<NSData *> *)chunkDigests
                         totalLength:(NSUInteger)totalLength
                               error:(NSError **)error {
    NSData *multihash = [cid isKindOfClass:[ATProtoCID class]] ? cid.multihash : nil;
    const uint8_t *multihashBytes = multihash.bytes;
    if (![cid isKindOfClass:[ATProtoCID class]] ||
        ![cid isDASLConformantForProfile:ATProtoDASLCIDProfileBig] ||
        multihash.length < 2 || multihashBytes[0] != ATProtoDASLMultihashBLAKE3) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorInvalidCID,
                                        @"BDASL requires a conformant BLAKE3 CID");
        return nil;
    }

    NSUInteger quotient = totalLength / ATProtoBDASLChunkSize;
    NSUInteger remainder = totalLength % ATProtoBDASLChunkSize;
    NSUInteger expectedChunks = quotient + (remainder > 0 ? 1 : 0);
    if (expectedChunks == 0) {
        expectedChunks = 1;
    }
    if (![chunkDigests isKindOfClass:[NSArray class]] ||
        chunkDigests.count != expectedChunks) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorInvalidSidecar,
                                        @"Sidecar chunk count does not match payload length");
        return nil;
    }
    for (NSData *digest in chunkDigests) {
        if (![digest isKindOfClass:[NSData class]] || digest.length != kBDASLDigestLength) {
            if (error) *error = BDASLError(ATProtoBDASLVerifierErrorInvalidSidecar,
                                            @"Each sidecar chunk digest must be 32 bytes");
            return nil;
        }
    }

    self = [super init];
    if (self) {
        _cid = cid;
        _chunkDigests = [chunkDigests copy];
        _totalLength = totalLength;
        _pendingChunk = [NSMutableData dataWithCapacity:ATProtoBDASLChunkSize];
        _rootHasher = [[ATProtoBDASLRootHasher alloc] init];
    }
    return self;
}

- (BOOL)appendData:(NSData *)data error:(NSError **)error {
    if (self.verified || self.failed) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorIncomplete,
                                        @"A completed or failed BDASL stream cannot accept more data");
        return NO;
    }
    if (![data isKindOfClass:[NSData class]]) {
        self.failed = YES;
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorTooMuchData,
                                        @"Stream data must be NSData");
        return NO;
    }
    if (self.bytesReceived > self.totalLength || data.length > self.totalLength - self.bytesReceived) {
        self.failed = YES;
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorTooMuchData,
                                        @"Stream contains more bytes than the sidecar declares");
        return NO;
    }

    [self.rootHasher updateWithData:data];
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) {
        NSUInteger take = MIN(ATProtoBDASLChunkSize - self.pendingChunk.length,
                              data.length - offset);
        [self.pendingChunk appendBytes:bytes + offset length:take];
        offset += take;
        self.bytesReceived += take;

        BOOL finalChunk = self.bytesReceived == self.totalLength;
        if (self.pendingChunk.length == ATProtoBDASLChunkSize || finalChunk) {
            blake3_hasher hasher;
            blake3_hasher_init(&hasher);
            blake3_hasher_update(&hasher, self.pendingChunk.bytes, self.pendingChunk.length);
            uint8_t digest[kBDASLDigestLength];
            blake3_hasher_finalize(&hasher, digest, sizeof(digest));
            NSData *actual = [NSData dataWithBytes:digest length:sizeof(digest)];
            NSData *expected = self.chunkDigests[self.nextChunkIndex];
            if (![actual isEqualToData:expected]) {
                self.failed = YES;
                if (error) *error = BDASLError(ATProtoBDASLVerifierErrorChunkMismatch,
                                                [NSString stringWithFormat:@"BDASL chunk %lu failed verification", (unsigned long)self.nextChunkIndex]);
                return NO;
            }
            self.verifiedChunkCount += 1;
            self.nextChunkIndex += 1;
            [self.pendingChunk setLength:0];
        }
    }
    return YES;
}

- (BOOL)finalizeWithError:(NSError **)error {
    if (self.verified) return YES;
    if (self.failed) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorIncomplete,
                                        @"Cannot finalize a failed BDASL stream");
        return NO;
    }
    if (self.totalLength == 0 && self.verifiedChunkCount == 0 &&
        self.chunkDigests.count == 1) {
        blake3_hasher emptyHasher;
        blake3_hasher_init(&emptyHasher);
        uint8_t emptyDigest[kBDASLDigestLength];
        blake3_hasher_finalize(&emptyHasher, emptyDigest, sizeof(emptyDigest));
        if (![self.chunkDigests[0] isEqualToData:[NSData dataWithBytes:emptyDigest length:sizeof(emptyDigest)]]) {
            self.failed = YES;
            if (error) *error = BDASLError(ATProtoBDASLVerifierErrorChunkMismatch,
                                            @"BDASL empty chunk failed verification");
            return NO;
        }
        self.verifiedChunkCount = 1;
    }
    if (self.bytesReceived != self.totalLength || self.pendingChunk.length != 0 ||
        self.verifiedChunkCount != self.chunkDigests.count) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorIncomplete,
                                        @"Stream ended before all BDASL chunks were verified");
        return NO;
    }

    NSData *multihash = self.cid.multihash;
    NSData *expectedDigest = [multihash subdataWithRange:NSMakeRange(2, multihash.length - 2)];
    NSData *actualDigest = [self.rootHasher finalDigest];
    if (![actualDigest isEqualToData:expectedDigest]) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorRootMismatch,
                                        @"BDASL payload does not match its CID root digest");
        return NO;
    }
    self.verified = YES;
    return YES;
}

+ (BOOL)chunkRangeForStart:(NSUInteger)start
                  hasStart:(BOOL)hasStart
                       end:(NSUInteger)end
                    hasEnd:(BOOL)hasEnd
               totalLength:(NSUInteger)totalLength
                firstChunk:(NSUInteger *)firstChunk
                 lastChunk:(NSUInteger *)lastChunk
                     error:(NSError **)error {
    if (totalLength == 0 || (hasStart && start >= totalLength) || (hasEnd && end < start)) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorInvalidRange,
                                        @"HTTP range does not intersect the payload");
        return NO;
    }
    NSUInteger effectiveStart = hasStart ? start : 0;
    NSUInteger effectiveEnd = hasEnd ? MIN(end, totalLength - 1) : totalLength - 1;
    if (effectiveStart > effectiveEnd) {
        if (error) *error = BDASLError(ATProtoBDASLVerifierErrorInvalidRange,
                                        @"HTTP range is invalid");
        return NO;
    }
    // Chunk indices are zero-based floor divisions: a range touching byte 1023
    // still touches chunk 0, while byte 1024 begins chunk 1. This is the
    // containing-chunk interpretation illustrated by the BDASL examples.
    if (firstChunk) *firstChunk = effectiveStart / ATProtoBDASLChunkSize;
    if (lastChunk) *lastChunk = effectiveEnd / ATProtoBDASLChunkSize;
    return YES;
}

@end

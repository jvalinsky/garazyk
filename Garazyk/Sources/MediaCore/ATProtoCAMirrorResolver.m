// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoCAMirrorResolver.h"

#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/ATProtoBao.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"

NSErrorDomain const ATProtoCAMirrorResolverErrorDomain = @"ATProtoCAMirrorResolverErrorDomain";

static NSError *CAMirrorError(ATProtoCAMirrorResolverErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoCAMirrorResolverErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

@implementation ATProtoCAMirrorResolver

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                            fetcher:(id<ATProtoCAMirrorFetching>)fetcher {
    NSParameterAssert(objectStore);
    self = [super init];
    if (self) {
        _objectStore = objectStore;
        _fetcher = fetcher;
        _mirrorFetchEnabled = NO;
    }
    return self;
}

- (ATProtoCAObjectDigestProfile)digestProfileForCID:(ATProtoCID *)cid {
    NSData *mh = cid.multihash;
    if (mh.length >= 2 && ((const uint8_t *)mh.bytes)[0] == ATProtoDASLMultihashBLAKE3) {
        return ATProtoCAObjectDigestProfileBLAKE3;
    }
    return ATProtoCAObjectDigestProfileSHA256;
}

- (BOOL)cid:(ATProtoCID *)cid matchesData:(NSData *)data {
    ATProtoCAObjectDigestProfile profile = [self digestProfileForCID:cid];
    if (profile == ATProtoCAObjectDigestProfileBLAKE3) {
        if (![cid isDASLConformantForProfile:ATProtoDASLCIDProfileBig]) {
            return NO;
        }
        NSData *root = [ATProtoBao hashForData:data];
        NSData *mh = cid.multihash;
        if (mh.length < 34) {
            return NO;
        }
        NSData *digest = [mh subdataWithRange:NSMakeRange(2, 32)];
        return [digest isEqualToData:root];
    }
    if (![cid isDASLConformantForProfile:ATProtoDASLCIDProfileBase]) {
        return NO;
    }
    ATProtoCID *computed = [ATProtoCAObjectStore cidForData:data
                                                    profile:ATProtoCAObjectDigestProfileSHA256
                                                      error:nil];
    return [computed isEqualToCID:cid];
}

- (nullable NSData *)fetchAndStoreObjectForCID:(ATProtoCID *)cid
                                     providers:(NSArray<NSString *> *)providers
                                         error:(NSError **)error {
    if (!self.mirrorFetchEnabled) {
        if (error) *error = CAMirrorError(ATProtoCAMirrorResolverErrorDisabled, @"Mirror fetch disabled");
        return nil;
    }
    if (!self.fetcher) {
        if (error) *error = CAMirrorError(ATProtoCAMirrorResolverErrorFetchFailed, @"No mirror fetcher configured");
        return nil;
    }
    if (providers.count == 0) {
        if (error) *error = CAMirrorError(ATProtoCAMirrorResolverErrorNotFound, @"No providers");
        return nil;
    }

    NSError *fetchError = nil;
    NSData *candidate = [self.fetcher fetchObjectBytesForCID:cid providers:providers error:&fetchError];
    if (!candidate) {
        if (error) {
            *error = fetchError ?: CAMirrorError(ATProtoCAMirrorResolverErrorFetchFailed, @"Mirror fetch failed");
        }
        return nil;
    }
    if (![self cid:cid matchesData:candidate]) {
        if (error) *error = CAMirrorError(ATProtoCAMirrorResolverErrorVerificationFailed,
                                          @"Mirror bytes do not match CID digest");
        return nil;
    }
    ATProtoCAObjectDigestProfile profile = [self digestProfileForCID:cid];
    NSError *putError = nil;
    ATProtoCID *stored = [self.objectStore putData:candidate
                                       expectedCID:cid
                                           profile:profile
                                             error:&putError];
    if (!stored) {
        if (error) *error = putError ?: CAMirrorError(ATProtoCAMirrorResolverErrorFetchFailed, @"Failed to store verified object");
        return nil;
    }
    return candidate;
}

- (nullable NSData *)dataForCID:(ATProtoCID *)cid
                      providers:(NSArray<NSString *> *)providers
                          error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAMirrorError(ATProtoCAMirrorResolverErrorInvalidArgument, @"CID required");
        return nil;
    }
    NSError *localError = nil;
    NSData *local = [self.objectStore dataForCID:cid error:&localError];
    if (local) {
        return local;
    }
    return [self fetchAndStoreObjectForCID:cid providers:providers ?: @[] error:error];
}

- (nullable NSData *)dataForCID:(ATProtoCID *)cid
                         offset:(NSUInteger)offset
                         length:(NSUInteger)length
                      providers:(NSArray<NSString *> *)providers
                          error:(NSError **)error {
    if (!cid) {
        if (error) *error = CAMirrorError(ATProtoCAMirrorResolverErrorInvalidArgument, @"CID required");
        return nil;
    }

    NSError *localError = nil;
    NSData *local = [self.objectStore dataForCID:cid offset:offset length:length error:&localError];
    if (local) {
        return local;
    }
    // Distinguish missing object from empty/past-EOF range: if the object exists, return the range result.
    NSDictionary *stat = [self.objectStore statCID:cid error:nil];
    if (stat) {
        if (error) *error = localError;
        return local;
    }

    if (!self.mirrorFetchEnabled || !self.fetcher || providers.count == 0) {
        if (error) {
            *error = localError ?: CAMirrorError(ATProtoCAMirrorResolverErrorNotFound, @"Object not found locally");
        }
        return nil;
    }

    NSData *rootHash = nil;
    NSData *mh = cid.multihash;
    if (mh.length >= 34) {
        rootHash = [mh subdataWithRange:NSMakeRange(2, 32)];
    }

    if (rootHash && [self.fetcher respondsToSelector:@selector(fetchBaoSliceForCID:rootHash:providers:offset:length:error:)]) {
        NSError *sliceError = nil;
        NSData *slice = [self.fetcher fetchBaoSliceForCID:cid
                                                 rootHash:rootHash
                                                providers:providers
                                                   offset:offset
                                                   length:length
                                                    error:&sliceError];
        if (slice) {
            NSData *verified = [ATProtoBao verifiedContentFromSlice:slice
                                                       expectedHash:rootHash
                                                             offset:offset
                                                             length:length
                                                              error:&sliceError];
            if (verified) {
                return verified;
            }
            // Fall through to full-object fetch on slice verify failure.
        }
    }

    NSData *full = [self fetchAndStoreObjectForCID:cid providers:providers error:error];
    if (!full) {
        return nil;
    }
    return [self.objectStore dataForCID:cid offset:offset length:length error:error];
}

@end

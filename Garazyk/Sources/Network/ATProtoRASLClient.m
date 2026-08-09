// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/ATProtoRASLClient.h"
#import "Core/ATProtoBDASLVerifier.h"
#import "Core/ATProtoRASLURL.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/ATProtoSafeHTTPClient.h"

NSErrorDomain const ATProtoRASLClientErrorDomain = @"com.atproto.rasl.client";

/** Multihash code for SHA-256 — the only algorithm this client verifies today. */
static const uint8_t kATProtoRASLMultihashSHA256 = 0x12;

static NSError *ATProtoRASLBDASLError(ATProtoRASLClientErrorCode code,
                                      NSString *message,
                                      NSError *underlyingError) {
    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey: message} mutableCopy];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                code:code
                            userInfo:userInfo];
}

@interface ATProtoRASLClient ()
@property (nonatomic, strong) id<ATProtoRASLHTTPFetching> httpClient;
@end

@implementation ATProtoRASLClient

+ (instancetype)sharedClient {
    static ATProtoRASLClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ATProtoRASLClient alloc]
            initWithHTTPClient:(id<ATProtoRASLHTTPFetching>)[ATProtoSafeHTTPClient sharedClient]];
    });
    return shared;
}

- (instancetype)initWithHTTPClient:(id<ATProtoRASLHTTPFetching>)httpClient {
    NSParameterAssert(httpClient != nil);
    self = [super init];
    if (self) {
        _httpClient = httpClient;
    }
    return self;
}

- (void)fetchDataForRASLURL:(ATProtoRASLURL *)url
            maxResponseBytes:(NSUInteger)maxResponseBytes
                      timeout:(NSTimeInterval)timeout
                   completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion {
    if (url.hints.count == 0) {
        completion(nil, [NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                             code:ATProtoRASLClientErrorNoHints
                                         userInfo:@{NSLocalizedDescriptionKey: @"rasl:// URL has no usable hints"}]);
        return;
    }

    NSData *multihash = url.cid.multihash;
    if (multihash.length < 2) {
        completion(nil, [NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                             code:ATProtoRASLClientErrorUnsupportedHashAlgorithm
                                         userInfo:@{NSLocalizedDescriptionKey: @"CID multihash is malformed"}]);
        return;
    }
    const uint8_t *multihashBytes = multihash.bytes;
    uint8_t hashAlgorithm = multihashBytes[0];
    if (hashAlgorithm != kATProtoRASLMultihashSHA256) {
        completion(nil, [NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                             code:ATProtoRASLClientErrorUnsupportedHashAlgorithm
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             @"Only SHA-256 (base DASL) CIDs are verified today; "
                                             @"BLAKE3 verification lands with the Phase 6 streaming verifier"}]);
        return;
    }
    NSData *expectedDigest = [multihash subdataWithRange:NSMakeRange(2, multihash.length - 2)];
    NSString *path = [url wellKnownPath];

    NSObject *stateLock = [[NSObject alloc] init];
    __block BOOL completed = NO;
    __block NSUInteger remaining = url.hints.count;
    NSMutableArray<NSError *> *failures = [NSMutableArray array];

    ATProtoSafeHTTPClientOptions *options = [[ATProtoSafeHTTPClientOptions alloc] init];
    options.timeout = timeout;
    options.maxResponseBytes = maxResponseBytes;
    options.allowHTTP = NO;
    options.allowPrivateHosts = NO;
    options.followRedirects = YES;

    void (^finishOnce)(NSData * _Nullable, NSError * _Nullable) =
        ^(NSData * _Nullable data, NSError * _Nullable error) {
            @synchronized(stateLock) {
                if (completed) {
                    return;
                }
                completed = YES;
            }
            completion(data, error);
        };

    // Not true cancellation: ATProtoSafeHTTPClient exposes no cancel handle, so
    // losing hints keep running to completion in the background; their results
    // are just dropped once `completed` is set. See file header discussion.
    void (^recordFailure)(NSError * _Nullable) = ^(NSError * _Nullable failure) {
        BOOL isLast = NO;
        @synchronized(stateLock) {
            if (completed) {
                return;
            }
            if (failure) {
                [failures addObject:failure];
            }
            remaining -= 1;
            isLast = (remaining == 0);
        }
        if (isLast) {
            NSError *aggregate =
                [NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                     code:ATProtoRASLClientErrorAllHintsFailed
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                         @"All %lu RASL hints failed", (unsigned long)failures.count],
                                     @"ATProtoRASLHintFailures": [failures copy]
                                 }];
            finishOnce(nil, aggregate);
        }
    };

    for (NSString *hint in url.hints) {
        NSString *urlString = [NSString stringWithFormat:@"https://%@%@", hint, path];
        NSURL *requestURL = [NSURL URLWithString:urlString];
        if (!requestURL) {
            recordFailure([NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                               code:ATProtoRASLClientErrorHintFailed
                                           userInfo:@{NSLocalizedDescriptionKey:
                                               [NSString stringWithFormat:@"Could not build a URL for hint %@", hint]}]);
            continue;
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
        request.HTTPMethod = @"GET";

            [[ATProtoSafeHTTPClient sharedClient]
            performSafeDataTaskWithRequest:request
                                    options:options
                                 completion:^(NSData * _Nullable data,
                                              NSHTTPURLResponse * _Nullable response,
                                              NSError * _Nullable error) {
            if (error) {
                recordFailure([NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                                   code:ATProtoRASLClientErrorHintFailed
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"Hint %@: %@", hint, error.localizedDescription],
                                                          NSUnderlyingErrorKey: error}]);
                return;
            }
            if (response.statusCode != 200) {
                recordFailure([NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                                   code:ATProtoRASLClientErrorHintFailed
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"Hint %@ returned HTTP %ld", hint, (long)response.statusCode]}]);
                return;
            }
            if (!data) {
                recordFailure([NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                                   code:ATProtoRASLClientErrorHintFailed
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"Hint %@ returned no body", hint]}]);
                return;
            }

            NSData *actualDigest = [ATProtoCID sha256Digest:data];
            if (![actualDigest isEqualToData:expectedDigest]) {
                recordFailure([NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                                   code:ATProtoRASLClientErrorHintFailed
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"Hint %@ returned data that does not hash to the requested CID", hint]}]);
                return;
            }

            finishOnce(data, nil);
        }];
    }
}

- (void)fetchBDASLDataForRASLURL:(ATProtoRASLURL *)url
                    chunkDigests:(NSArray<NSData *> *)chunkDigests
                     totalLength:(NSUInteger)totalLength
                 maxResponseBytes:(NSUInteger)maxResponseBytes
                           timeout:(NSTimeInterval)timeout
                        completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    if (url.hints.count == 0) {
        completion(nil, [NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                             code:ATProtoRASLClientErrorNoHints
                                         userInfo:@{NSLocalizedDescriptionKey: @"rasl:// URL has no usable hints"}]);
        return;
    }
    if (totalLength == 0) {
        completion(nil, ATProtoRASLBDASLError(ATProtoRASLClientErrorInvalidBDASLSidecar,
                                              @"BDASL HTTP range retrieval requires a non-empty payload",
                                              nil));
        return;
    }

    NSError *verifierError = nil;
    ATProtoBDASLVerifier *verifier = [[ATProtoBDASLVerifier alloc]
        initWithCID:url.cid
        chunkDigests:chunkDigests
        totalLength:totalLength
        error:&verifierError];
    if (!verifier) {
        completion(nil, ATProtoRASLBDASLError(ATProtoRASLClientErrorInvalidBDASLSidecar,
                                              @"The caller-supplied BDASL sidecar is invalid",
                                              verifierError));
        return;
    }

    NSUInteger firstChunk = 0;
    NSUInteger lastChunk = 0;
    NSError *rangeError = nil;
    if (![ATProtoBDASLVerifier chunkRangeForStart:0
                                          hasStart:YES
                                               end:totalLength - 1
                                            hasEnd:YES
                                       totalLength:totalLength
                                        firstChunk:&firstChunk
                                         lastChunk:&lastChunk
                                             error:&rangeError]) {
        completion(nil, ATProtoRASLBDASLError(ATProtoRASLClientErrorInvalidBDASLSidecar,
                                              @"The BDASL payload length cannot be mapped to chunks",
                                              rangeError));
        return;
    }

    NSUInteger largestChunkLength = ATProtoBDASLChunkSize;
    if (maxResponseBytes > 0 && maxResponseBytes < largestChunkLength &&
        (lastChunk > firstChunk || totalLength >= largestChunkLength)) {
        completion(nil, ATProtoRASLBDASLError(ATProtoRASLClientErrorInvalidBDASLSidecar,
                                              @"The response limit is smaller than a required BDASL chunk",
                                              nil));
        return;
    }

    ATProtoSafeHTTPClientOptions *options = [[ATProtoSafeHTTPClientOptions alloc] init];
    options.timeout = timeout;
    options.maxResponseBytes = maxResponseBytes;
    options.allowHTTP = NO;
    options.allowPrivateHosts = NO;
    options.followRedirects = YES;

    __weak ATProtoRASLClient *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ATProtoRASLClient *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        NSMutableData *assembled = [NSMutableData dataWithCapacity:totalLength];
        NSString *path = [url wellKnownPath];
        for (NSUInteger chunkIndex = firstChunk; chunkIndex <= lastChunk; chunkIndex++) {
            NSUInteger chunkStart = chunkIndex * ATProtoBDASLChunkSize;
            NSUInteger chunkLength = MIN(ATProtoBDASLChunkSize, totalLength - chunkStart);
            NSUInteger chunkEnd = chunkStart + chunkLength - 1;
            NSData *verifiedChunk = nil;
            NSMutableArray<NSError *> *hintFailures = [NSMutableArray array];

            for (NSString *hint in url.hints) {
                NSString *urlString = [NSString stringWithFormat:@"https://%@%@", hint, path];
                NSURL *requestURL = [NSURL URLWithString:urlString];
                if (!requestURL) {
                    [hintFailures addObject:ATProtoRASLBDASLError(
                        ATProtoRASLClientErrorHintFailed,
                        [NSString stringWithFormat:@"Could not build a URL for hint %@", hint],
                        nil)];
                    continue;
                }

                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
                request.HTTPMethod = @"GET";
                [request setValue:[NSString stringWithFormat:@"bytes=%llu-%llu",
                                   (unsigned long long)chunkStart,
                                   (unsigned long long)chunkEnd]
                    forHTTPHeaderField:@"Range"];

                NSError *requestError = nil;
                NSHTTPURLResponse *response = nil;
                NSData *data = [strongSelf.httpClient sendSynchronousRequest:request
                                                                      options:options
                                                                     response:&response
                                                                        error:&requestError];
                if (requestError) {
                    [hintFailures addObject:ATProtoRASLBDASLError(
                        ATProtoRASLClientErrorHintFailed,
                        [NSString stringWithFormat:@"Hint %@ failed for BDASL chunk %lu",
                         hint, (unsigned long)chunkIndex],
                        requestError)];
                    continue;
                }
                if (response.statusCode != 206) {
                    [hintFailures addObject:ATProtoRASLBDASLError(
                        ATProtoRASLClientErrorHintFailed,
                        [NSString stringWithFormat:@"Hint %@ returned HTTP %ld for BDASL chunk %lu",
                         hint, (long)response.statusCode, (unsigned long)chunkIndex],
                        nil)];
                    continue;
                }
                if (data.length != chunkLength) {
                    [hintFailures addObject:ATProtoRASLBDASLError(
                        ATProtoRASLClientErrorHintFailed,
                        [NSString stringWithFormat:@"Hint %@ returned %lu bytes for a %lu-byte BDASL chunk",
                         hint, (unsigned long)data.length, (unsigned long)chunkLength],
                        nil)];
                    continue;
                }

                NSError *chunkError = nil;
                if (![ATProtoBDASLVerifier verifyChunkData:data
                                            expectedDigest:chunkDigests[chunkIndex]
                                                     error:&chunkError]) {
                    [hintFailures addObject:ATProtoRASLBDASLError(
                        ATProtoRASLClientErrorHintFailed,
                        [NSString stringWithFormat:@"Hint %@ returned an invalid BDASL chunk %lu",
                         hint, (unsigned long)chunkIndex],
                        chunkError)];
                    continue;
                }
                verifiedChunk = data;
                break;
            }

            if (!verifiedChunk) {
                NSError *failure = [NSError errorWithDomain:ATProtoRASLClientErrorDomain
                                                        code:ATProtoRASLClientErrorBDASLRangeFailed
                                                    userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"All RASL hints failed for BDASL chunk %lu", (unsigned long)chunkIndex],
                    @"ATProtoBDASLChunkIndex": @(chunkIndex),
                    @"ATProtoRASLHintFailures": [hintFailures copy]
                }];
                completion(nil, failure);
                return;
            }
            [assembled appendData:verifiedChunk];
        }

        NSError *verificationError = nil;
        if (![verifier appendData:assembled error:&verificationError] ||
            ![verifier finalizeWithError:&verificationError]) {
            completion(nil, ATProtoRASLBDASLError(ATProtoRASLClientErrorBDASLRangeFailed,
                                                  @"The assembled BDASL payload failed CID verification",
                                                  verificationError));
            return;
        }
        completion(assembled, nil);
    });
}

@end

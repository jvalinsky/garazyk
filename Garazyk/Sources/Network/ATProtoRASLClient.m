// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/ATProtoRASLClient.h"
#import "Core/ATProtoRASLURL.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Network/ATProtoSafeHTTPClient.h"

NSErrorDomain const ATProtoRASLClientErrorDomain = @"com.atproto.rasl.client";

/** Multihash code for SHA-256 — the only algorithm this client verifies today. */
static const uint8_t kATProtoRASLMultihashSHA256 = 0x12;

@implementation ATProtoRASLClient

+ (instancetype)sharedClient {
    static ATProtoRASLClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ATProtoRASLClient alloc] init];
    });
    return shared;
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

            NSData *actualDigest = [CID sha256Digest:data];
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

@end

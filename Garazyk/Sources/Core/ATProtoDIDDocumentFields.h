// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class DIDDocument;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoDIDDocumentFields : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (nullable NSString *)normalizedHandleFromDocument:(DIDDocument *)document;
+ (nullable NSString *)pdsEndpointFromDocument:(DIDDocument *)document;
+ (nullable NSString *)atprotoSigningKeyMultibaseFromDocument:(DIDDocument *)document;

/**
 * Selects only the canonical account signing key (`#atproto`). Unlike the
 * historical helper above, this never falls back to an arbitrary method.
 */
+ (nullable NSString *)strictAtprotoSigningKeyMultibaseFromDocument:(DIDDocument *)document;

/**
 * Selects the proposal-0016 authority key with an exact fragment match.
 * `#atproto_space` is preferred; only the documented `#atproto` fallback is
 * used when no dedicated key is published.
 */
+ (nullable NSString *)spaceSigningKeyMultibaseFromDocument:(DIDDocument *)document;

/** Returns only a published dedicated `#atproto_space` signing key. */
+ (nullable NSString *)dedicatedSpaceSigningKeyMultibaseFromDocument:(DIDDocument *)document;

/**
 * Selects and validates the proposal-0016 space-host endpoint. The dedicated
 * `#atproto_space_host` service wins; `#atproto_pds` is the sole fallback.
 */
+ (nullable NSString *)spaceHostEndpointFromDocument:(DIDDocument *)document;

@end

NS_ASSUME_NONNULL_END

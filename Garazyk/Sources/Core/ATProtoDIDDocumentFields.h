// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class ATProtoDIDDocument;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoDIDDocumentFields : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (nullable NSString *)normalizedHandleFromDocument:(ATProtoDIDDocument *)document;
+ (nullable NSString *)pdsEndpointFromDocument:(ATProtoDIDDocument *)document;
+ (nullable NSString *)atprotoSigningKeyMultibaseFromDocument:(ATProtoDIDDocument *)document;

/**
 * Selects only the canonical account signing key (`#atproto`). Unlike the
 * historical helper above, this never falls back to an arbitrary method.
 */
+ (nullable NSString *)strictAtprotoSigningKeyMultibaseFromDocument:(ATProtoDIDDocument *)document;

/**
 * Selects the proposal-0016 authority key with an exact fragment match.
 * `#atproto_space` is preferred; only the documented `#atproto` fallback is
 * used when no dedicated key is published.
 */
+ (nullable NSString *)spaceSigningKeyMultibaseFromDocument:(ATProtoDIDDocument *)document;

/** Returns only a published dedicated `#atproto_space` signing key. */
+ (nullable NSString *)dedicatedSpaceSigningKeyMultibaseFromDocument:(ATProtoDIDDocument *)document;

/**
 * Selects and validates the proposal-0016 space-host endpoint. The dedicated
 * `#atproto_space_host` service wins; `#atproto_pds` is the sole fallback.
 */
+ (nullable NSString *)spaceHostEndpointFromDocument:(ATProtoDIDDocument *)document;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczStreamplaceOriginHints.h

 @abstract Env + place.stream.media.origin helpers for WS15 mirror providers.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GZJelczStreamplaceOriginHints : NSObject

/**
 Returns a normalized absolute HTTPS base, or nil if @c base is empty/invalid.
 */
+ (nullable NSString *)normalizedProviderBaseURL:(nullable NSString *)base;

/**
 Merges an operator Streamplace base into an existing provider list (deduped).
 */
+ (NSArray<NSString *> *)providersByMergingStreamplaceBase:(nullable NSString *)streamplaceBase
                                        existingProviders:(nullable NSArray<NSString *> *)existing;

/**
 When @c originRecord contains a @c blob matching @c cidString and a configured
 base is present, returns @[base]. Firehose multi-origin indexing is deferred.
 */
+ (nullable NSArray<NSString *> *)providersForCIDString:(NSString *)cidString
                                          originRecord:(nullable NSDictionary *)originRecord
                                    configuredBaseURL:(nullable NSString *)configuredBaseURL;

/**
 Builds a @c place.stream.media.origin record dictionary (not published).
 */
+ (NSDictionary *)originRecordForBlobCID:(NSString *)cidString
                                    size:(NSUInteger)size
                                mimeType:(NSString *)mimeType;

@end

NS_ASSUME_NONNULL_END

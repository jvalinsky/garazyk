// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayIngressConfiguration.h

 @abstract Validated limits and watermarks for relay ingress admission.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RelayIngressConfigurationErrorDomain;

typedef NS_ENUM(NSInteger, RelayIngressConfigurationErrorCode) {
    RelayIngressConfigurationErrorCodeInvalidLimits = 1,
    RelayIngressConfigurationErrorCodeInvalidWatermarks = 2,
    RelayIngressConfigurationErrorCodeOverflow = 3,
};

/**
 * @abstract Immutable relay ingress resource envelope.
 */
@interface ATProtoRelayIngressConfiguration : NSObject

@property (nonatomic, assign, readonly) NSUInteger maxEventCount;
@property (nonatomic, assign, readonly) uint64_t maxByteCount;
@property (nonatomic, assign, readonly) NSUInteger lowEventWatermark;
@property (nonatomic, assign, readonly) uint64_t lowByteWatermark;
@property (nonatomic, assign, readonly) NSUInteger highEventWatermark;
@property (nonatomic, assign, readonly) uint64_t highByteWatermark;
@property (nonatomic, assign, readonly) NSUInteger shardCount;
/** When NO, the legacy main-queue/handler-queue path is used. */
@property (nonatomic, assign, readonly) BOOL boundedIngressEnabled;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * @abstract Returns the default small-host envelope from workstream 17.
 */
+ (instancetype)defaultConfiguration;

/**
 * @abstract Builds configuration from environment and optional JSON overrides.
 */
+ (nullable instancetype)configurationFromEnvironment:(NSError * _Nullable * _Nullable)error;

/**
 * @abstract Validates explicit limits. Returns nil and sets error on failure.
 */
+ (nullable instancetype)configurationWithMaxEventCount:(NSUInteger)maxEvents
                                           maxByteCount:(uint64_t)maxBytes
                                     lowEventWatermark:(NSUInteger)lowEvents
                                       lowByteWatermark:(uint64_t)lowBytes
                                    highEventWatermark:(NSUInteger)highEvents
                                      highByteWatermark:(uint64_t)highBytes
                                             shardCount:(NSUInteger)shardCount
                                  boundedIngressEnabled:(BOOL)boundedIngressEnabled
                                                  error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSecretsProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Defines PDSEnvironmentSecretsProviderError values exposed by this API.
 */
typedef NS_ENUM(NSInteger, PDSEnvironmentSecretsProviderError) {
    PDSEnvironmentSecretsProviderErrorInvalidKey = 1,
    PDSEnvironmentSecretsProviderErrorKeyNotFound = 2
};

/**
 * @abstract Declares the PDSEnvironmentSecretsProvider public API.
 */
@interface PDSEnvironmentSecretsProvider : NSObject <PDSSecretsProvider>

/**
 * @abstract Exposes the key prefix value.
 */
@property (nonatomic, copy, readonly) NSString *keyPrefix;

/**
 * @abstract Performs the initWithPrefix operation.
 */
- (instancetype)initWithPrefix:(nullable NSString *)prefix NS_DESIGNATED_INITIALIZER;
/**
 * @abstract Returns the init result.
 */
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END

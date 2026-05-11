// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "PDSEmailProvider.h"
#import "PDSSecretsProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSResendEmailProvider : NSObject <PDSEmailProvider>

/**
 * The email address to send from (e.g., "onboarding@resend.dev").
 */
@property (nonatomic, copy, readonly) NSString *fromAddress;

/**
 * The API endpoint base URL (default: "https://api.resend.com").
 */
@property (nonatomic, copy, readonly) NSString *apiEndpoint;

/**
 * The secrets provider used to retrieve the API key.
 */
@property (nonatomic, strong, readonly) id<PDSSecretsProvider> secretsProvider;

/**
 * Designated initializer.
 * @param secretsProvider The provider for the API key.
 * @param fromAddress The sender email address.
 * @param apiEndpoint Custom API endpoint URL (optional, pass nil for default).
 */
- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                            fromAddress:(NSString *)fromAddress
                            apiEndpoint:(nullable NSString *)apiEndpoint NS_DESIGNATED_INITIALIZER;

/**
 * Convenience initializer using the default API endpoint.
 * @param secretsProvider The provider for the API key.
 * @param fromAddress The sender email address.
 */
- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                            fromAddress:(NSString *)fromAddress;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

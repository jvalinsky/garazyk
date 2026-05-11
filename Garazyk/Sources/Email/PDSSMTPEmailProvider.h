// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "PDSEmailProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSSMTPEmailProvider
 * @abstract SMTP provider configuration holder.
 * @discussion SMTP delivery is not implemented. Send attempts fail closed with
 * PDSSMTPEmailProviderErrorNotImplemented so configured deployments do not
 * report messages as delivered.
 */
extern NSString * const PDSSMTPEmailProviderErrorDomain;

typedef NS_ENUM(NSInteger, PDSSMTPEmailProviderError) {
    PDSSMTPEmailProviderErrorNotImplemented = 1,
};

@interface PDSSMTPEmailProvider : NSObject <PDSEmailProvider>

/** The SMTP server hostname. */
@property (nonatomic, copy) NSString *smtpHost;

/** The SMTP server port (e.g., 587 or 465). */
@property (nonatomic, assign) NSUInteger smtpPort;

/** The username for authentication. */
@property (nonatomic, copy, nullable) NSString *username;

/** The password for authentication. */
@property (nonatomic, copy, nullable) NSString *password;

/** Whether to use SSL/TLS. */
@property (nonatomic, assign) BOOL useTLS;

/**
 * Initializes the SMTP provider with server details.
 */
- (instancetype)initWithHost:(NSString *)host
                        port:(NSUInteger)port
                    username:(nullable NSString *)username
                    password:(nullable NSString *)password
                      useTLS:(BOOL)useTLS;

@end

NS_ASSUME_NONNULL_END

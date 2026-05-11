// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSEmailProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSMockEmailProvider
 * @abstract A mock email provider that records sent emails in memory for testing.
 */
@interface PDSMockEmailProvider : NSObject <PDSEmailProvider>

/**
 * An array of dictionaries representing the emails "sent" during the session.
 * Each dictionary contains: to, subject, body, and optionally htmlBody.
 */
@property (nonatomic, readonly) NSArray<NSDictionary *> *sentEmails;

/**
 * Clears the history of sent emails.
 */
- (void)clearSentEmails;

/**
 * Returns the most recently sent email, or nil if none.
 */
- (nullable NSDictionary *)lastSentEmail;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSEmailProvider
 @abstract Defines the interface for a pluggable email delivery system.
 @discussion
    Implementations can use SMTP, HTTP APIs (SendGrid/Mailgun), or mock for testing.
    The provider abstracts email delivery to allow easy switching between backends.
 */
@protocol PDSEmailProvider <NSObject>

/*!
 @method sendEmailTo:subject:body:error:
 @abstract Sends a plain text email message.
 @param to Recipient email address.
 @param subject Email subject line.
 @param body Email body content (text/plain).
 @param error Output error if sending fails.
 @return YES if the message was successfully queued/sent, NO otherwise.
 */
- (BOOL)sendEmailTo:(NSString *)to
            subject:(NSString *)subject
               body:(NSString *)body
              error:(NSError **)error;

/*!
 @method sendHtmlEmailTo:subject:htmlBody:textBody:error:
 @abstract Sends an HTML email message with plain text fallback.
 @param to Recipient email address.
 @param subject Email subject line.
 @param htmlBody Email body in HTML format.
 @param textBody Fallback email body in plain text format.
 @param error Output error if sending fails.
 @return YES if the message was successfully queued/sent, NO otherwise.
 */
- (BOOL)sendHtmlEmailTo:(NSString *)to
                subject:(NSString *)subject
               htmlBody:(NSString *)htmlBody
               textBody:(NSString *)textBody
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @protocol PDSEmailProvider
 * @abstract Defines the interface for a pluggable email delivery system.
 * @discussion Implementations can use SMTP, HTTP APIs (SendGrid/Mailgun), or mock for testing.
 */
@protocol PDSEmailProvider <NSObject>

/**
 * Sends an email message.
 * @param to recipient email address.
 * @param subject email subject line.
 * @param body email body (text/plain).
 * @param error output error if sending fails.
 * @return YES if the message was successfully queued/sent, NO otherwise.
 */
- (BOOL)sendEmailTo:(NSString *)to
            subject:(NSString *)subject
               body:(NSString *)body
              error:(NSError **)error;

/**
 * Sends a HTML email message.
 * @param to recipient email address.
 * @param subject email subject line.
 * @param htmlBody email body in HTML format.
 * @param textBody fallback email body in plain text.
 * @param error output error if sending fails.
 * @return YES if the message was successfully queued/sent, NO otherwise.
 */
- (BOOL)sendHtmlEmailTo:(NSString *)to
                subject:(NSString *)subject
               htmlBody:(NSString *)htmlBody
               textBody:(NSString *)textBody
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#import "PDSSMTPEmailProvider.h"
#import "Debug/PDSLogger.h"

@implementation PDSSMTPEmailProvider

- (instancetype)initWithHost:(NSString *)host
                        port:(NSUInteger)port
                    username:(nullable NSString *)username
                    password:(nullable NSString *)password
                      useTLS:(BOOL)useTLS {
    if (self = [super init]) {
        _smtpHost = [host copy];
        _smtpPort = port;
        _username = [username copy];
        _password = [password copy];
        _useTLS = useTLS;
    }
    return self;
}

#pragma mark - PDSEmailProvider

- (BOOL)sendEmailTo:(NSString *)to
            subject:(NSString *)subject
               body:(NSString *)body
              error:(NSError **)error {
    // SKELETON: In a real implementation, this would use a library like MailCore
    // or manually handle the SMTP handshake.
    PDS_LOG_INFO(@"[SMTP] Would send email to: %@, subject: %@ (using host: %@)", to, subject, self.smtpHost);
    
    // For now, we return YES and log that a production implementation is needed.
    return YES;
}

- (BOOL)sendHtmlEmailTo:(NSString *)to
                subject:(NSString *)subject
               htmlBody:(NSString *)htmlBody
               textBody:(NSString *)textBody
                  error:(NSError **)error {
    PDS_LOG_INFO(@"[SMTP] Would send HTML email to: %@, subject: %@ (using host: %@)", to, subject, self.smtpHost);
    return YES;
}

@end

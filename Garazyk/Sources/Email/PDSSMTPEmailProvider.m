#import "PDSSMTPEmailProvider.h"
#import "Debug/PDSLogger.h"

NSString * const PDSSMTPEmailProviderErrorDomain = @"com.atproto.pds.smtpemailprovider";

static NSError *PDSSMTPEmailProviderUnsupportedError(void) {
    return [NSError errorWithDomain:PDSSMTPEmailProviderErrorDomain
                               code:PDSSMTPEmailProviderErrorNotImplemented
                           userInfo:@{NSLocalizedDescriptionKey: @"SMTP email delivery is not implemented"}];
}

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
    PDS_LOG_WARN(@"[SMTP] Refusing to report email delivery for %@ because SMTP is not implemented (host: %@)", to, self.smtpHost);
    if (error) {
        *error = PDSSMTPEmailProviderUnsupportedError();
    }
    return NO;
}

- (BOOL)sendHtmlEmailTo:(NSString *)to
                subject:(NSString *)subject
               htmlBody:(NSString *)htmlBody
               textBody:(NSString *)textBody
                  error:(NSError **)error {
    PDS_LOG_WARN(@"[SMTP] Refusing to report HTML email delivery for %@ because SMTP is not implemented (host: %@)", to, self.smtpHost);
    if (error) {
        *error = PDSSMTPEmailProviderUnsupportedError();
    }
    return NO;
}

@end

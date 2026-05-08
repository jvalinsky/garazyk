#import "PDSResendEmailProvider.h"
#import "PDSEmailHTTPClient.h"
#import "Debug/PDSLogger.h"

// Suppress -Wblock-capture-autoreleasing: the error out-parameter captured
// by dispatch_sync in httpClientWithError: is safe because dispatch_sync
// completes before the method returns.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

static NSString *const kDefaultResendEndpoint = @"https://api.resend.com";
static NSString *const kResendAPIKeySecretName = @"RESEND_API_KEY";

@interface PDSResendEmailProvider () {
    dispatch_queue_t _initQueue;
}
@property (nonatomic, strong) PDSEmailHTTPClient *httpClient;

@end

@implementation PDSResendEmailProvider

@synthesize fromAddress = _fromAddress;
@synthesize apiEndpoint = _apiEndpoint;
@synthesize secretsProvider = _secretsProvider;

- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                            fromAddress:(NSString *)fromAddress
                            apiEndpoint:(nullable NSString *)apiEndpoint {
    self = [super init];
    if (self) {
        _secretsProvider = secretsProvider;
        _fromAddress = [fromAddress copy];
        _apiEndpoint = [apiEndpoint copy] ?: kDefaultResendEndpoint;
        _initQueue = dispatch_queue_create("com.atproto.resend.init", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                            fromAddress:(NSString *)fromAddress {
    return [self initWithSecretsProvider:secretsProvider fromAddress:fromAddress apiEndpoint:nil];
}

- (PDSEmailHTTPClient *)httpClientWithError:(NSError **)error {
    __block PDSEmailHTTPClient *client = nil;
    dispatch_sync(_initQueue, ^{
        if (_httpClient) {
            client = _httpClient;
            return;
        }

        NSString *apiKey = [self.secretsProvider secretForKey:kResendAPIKeySecretName error:error];
        if (!apiKey) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:@"PDSResendEmailProviderErrorDomain"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Missing Resend API Key"}];
            }
            return;
        }

        NSURL *baseURL = [NSURL URLWithString:self.apiEndpoint];
        if (!baseURL) {
            if (error) {
                *error = [NSError errorWithDomain:@"PDSResendEmailProviderErrorDomain"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid API Endpoint URL"}];
            }
            return;
        }

        _httpClient = [[PDSEmailHTTPClient alloc] initWithBaseURL:baseURL apiKey:apiKey];
        client = _httpClient;
    });
    return client;
}

#pragma mark - PDSEmailProvider

- (BOOL)sendEmailTo:(NSString *)to
            subject:(NSString *)subject
               body:(NSString *)body
              error:(NSError **)error {
    PDS_LOG_INFO(@"[Resend] Sending email to: %@ subject: %@", to, subject);

    NSError *localError = nil;
    PDSEmailHTTPClient *client = [self httpClientWithError:&localError];
    if (!client) {
        PDS_LOG_ERROR(@"[Resend] Failed to initialize client: %@", localError);
        if (error) {
            *error = localError;
        }
        return NO;
    }

    NSDictionary *payload = @{
        @"from": self.fromAddress,
        @"to": @[to],
        @"subject": subject,
        @"text": body
    };

    NSDictionary *response = [client postPath:@"/emails" body:payload error:&localError];
    if (response) {
        PDS_LOG_INFO(@"[Resend] Successfully sent email to: %@ (ID: %@)", to, response[@"id"]);
        return YES;
    } else {
        PDS_LOG_ERROR(@"[Resend] Failed to send email to: %@ error: %@", to, localError);
        if (error) {
            *error = localError;
        }
        return NO;
    }
}

- (BOOL)sendHtmlEmailTo:(NSString *)to
                subject:(NSString *)subject
               htmlBody:(NSString *)htmlBody
               textBody:(NSString *)textBody
                  error:(NSError **)error {
    PDS_LOG_INFO(@"[Resend] Sending HTML email to: %@ subject: %@", to, subject);

    NSError *localError = nil;
    PDSEmailHTTPClient *client = [self httpClientWithError:&localError];
    if (!client) {
        PDS_LOG_ERROR(@"[Resend] Failed to initialize client: %@", localError);
        if (error) {
            *error = localError;
        }
        return NO;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:@{
        @"from": self.fromAddress,
        @"to": @[to],
        @"subject": subject,
        @"html": htmlBody
    }];

    if (textBody) {
        payload[@"text"] = textBody;
    }

    NSDictionary *response = [client postPath:@"/emails" body:payload error:&localError];
    if (response) {
        PDS_LOG_INFO(@"[Resend] Successfully sent HTML email to: %@ (ID: %@)", to, response[@"id"]);
        return YES;
    } else {
        PDS_LOG_ERROR(@"[Resend] Failed to send HTML email to: %@ error: %@", to, localError);
        if (error) {
            *error = localError;
        }
        return NO;
    }
}

@end

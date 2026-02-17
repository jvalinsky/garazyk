#import "PDSResendEmailProvider.h"
#import "PDSEmailHTTPClient.h"

static NSString *const kDefaultResendEndpoint = @"https://api.resend.com";
static NSString *const kResendAPIKeySecretName = @"RESEND_API_KEY";

@interface PDSResendEmailProvider ()

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
    }
    return self;
}

- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                            fromAddress:(NSString *)fromAddress {
    return [self initWithSecretsProvider:secretsProvider fromAddress:fromAddress apiEndpoint:nil];
}

- (PDSEmailHTTPClient *)httpClientWithError:(NSError **)error {
    if (_httpClient) {
        return _httpClient;
    }

    NSString *apiKey = [self.secretsProvider secretForKey:kResendAPIKeySecretName error:error];
    if (!apiKey) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDSResendEmailProviderErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing Resend API Key"}];
        }
        return nil;
    }

    NSURL *baseURL = [NSURL URLWithString:self.apiEndpoint];
    if (!baseURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSResendEmailProviderErrorDomain"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid API Endpoint URL"}];
        }
        return nil;
    }

    _httpClient = [[PDSEmailHTTPClient alloc] initWithBaseURL:baseURL apiKey:apiKey];
    return _httpClient;
}

#pragma mark - PDSEmailProvider

- (BOOL)sendEmailTo:(NSString *)to
            subject:(NSString *)subject
               body:(NSString *)body
              error:(NSError **)error {
    PDSEmailHTTPClient *client = [self httpClientWithError:error];
    if (!client) {
        return NO;
    }

    NSDictionary *payload = @{
        @"from": self.fromAddress,
        @"to": @[to],
        @"subject": subject,
        @"text": body
    };

    return [client postPath:@"/emails" body:payload error:error] != nil;
}

- (BOOL)sendHtmlEmailTo:(NSString *)to
                subject:(NSString *)subject
               htmlBody:(NSString *)htmlBody
               textBody:(NSString *)textBody
                  error:(NSError **)error {
    PDSEmailHTTPClient *client = [self httpClientWithError:error];
    if (!client) {
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

    return [client postPath:@"/emails" body:payload error:error] != nil;
}

@end

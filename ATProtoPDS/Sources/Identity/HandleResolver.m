#import "Identity/HandleResolver.h"
#import "Identity/ATProtoHandleValidator.h"

NSString * const HandleErrorDomain = @"com.atproto.handle";

@implementation HandleResolver

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 30.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)resolveHandle:(NSString *)handle
           completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {
    
    if (!completion) return;
    
    // Validate handle
    NSError *validationError = nil;
    if (![ATProtoHandleValidator validateHandle:handle error:&validationError]) {
        completion(nil, validationError);
        return;
    }
    
    // Normalize handle
    handle = [ATProtoHandleValidator normalizeHandle:handle];
    
    // Try HTTPS resolution first
    [self resolveHandleViaHTTPS:handle completion:completion];
    
    // TODO: Add DNS TXT fallback if HTTPS fails
}

- (void)resolveHandleViaHTTPS:(NSString *)handle
                   completion:(void (^)(NSString * _Nullable did, NSError * _Nullable error))completion {
    
    NSString *urlString = [NSString stringWithFormat:@"https://%@/.well-known/atproto-did", handle];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        NSError *error = [NSError errorWithDomain:HandleErrorDomain
                                          code:HandleErrorInvalidFormat
                                      userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL constructed from handle"}];
        completion(nil, error);
        return;
    }
    
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                              completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (error) {
            // TODO: Try DNS TXT as fallback
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                      code:HandleErrorNetworkError
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Network error during handle resolution",
                                                            NSUnderlyingErrorKey: error}];
            completion(nil, resolveError);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            // TODO: Try DNS TXT as fallback
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                      code:HandleErrorNotFound
                                                  userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld when resolving handle", (long)httpResponse.statusCode]}];
            completion(nil, resolveError);
            return;
        }
        
        if (!data) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                      code:HandleErrorResolutionFailed
                                                  userInfo:@{NSLocalizedDescriptionKey: @"No data received from handle resolution"}];
            completion(nil, resolveError);
            return;
        }
        
        NSString *did = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        did = [did stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (!did || did.length == 0) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                      code:HandleErrorResolutionFailed
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Empty DID in handle resolution response"}];
            completion(nil, resolveError);
            return;
        }
        
        // Basic validation that it's a DID
        if (![did hasPrefix:@"did:"]) {
            NSError *resolveError = [NSError errorWithDomain:HandleErrorDomain
                                                      code:HandleErrorResolutionFailed
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Response does not contain a valid DID"}];
            completion(nil, resolveError);
            return;
        }
        
        completion(did, nil);
    }];
    
    [task resume];
}

@end
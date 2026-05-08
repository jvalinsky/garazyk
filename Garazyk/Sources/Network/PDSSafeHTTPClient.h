#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PDSSafeHTTPClientErrorDomain;

typedef NS_ENUM(NSInteger, PDSSafeHTTPClientErrorCode) {
    PDSSafeHTTPClientErrorInvalidURL = 1,
    PDSSafeHTTPClientErrorUnsupportedScheme = 2,
    PDSSafeHTTPClientErrorSSRFBlocked = 3,
    PDSSafeHTTPClientErrorResponseTooLarge = 4,
    PDSSafeHTTPClientErrorRedirectBlocked = 5,
};

@interface PDSSafeHTTPClientOptions : NSObject <NSCopying>

@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSUInteger maxResponseBytes;
@property (nonatomic, assign) BOOL allowHTTP;
@property (nonatomic, assign) BOOL allowPrivateHosts;
@property (nonatomic, assign) BOOL followRedirects;

+ (instancetype)defaultOptions;

@end

@interface PDSSafeHTTPClient : NSObject

+ (instancetype)sharedClient;

+ (BOOL)validateURL:(NSURL *)url
            options:(nullable PDSSafeHTTPClientOptions *)options
              error:(NSError **)error;

- (void)dataTaskWithRequest:(NSURLRequest *)request
                    options:(nullable PDSSafeHTTPClientOptions *)options
                 completion:(void (^)(NSData * _Nullable data,
                                      NSHTTPURLResponse * _Nullable response,
                                      NSError * _Nullable error))completion;

- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    options:(nullable PDSSafeHTTPClientOptions *)options
                                   response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

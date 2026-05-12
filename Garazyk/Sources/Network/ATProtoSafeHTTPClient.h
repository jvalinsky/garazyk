// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const ATProtoSafeHTTPClientErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoSafeHTTPClientErrorCode) {
    ATProtoSafeHTTPClientErrorInvalidURL = 1,
    ATProtoSafeHTTPClientErrorUnsupportedScheme = 2,
    ATProtoSafeHTTPClientErrorSSRFBlocked = 3,
    ATProtoSafeHTTPClientErrorResponseTooLarge = 4,
    ATProtoSafeHTTPClientErrorRedirectBlocked = 5,
};

@interface ATProtoSafeHTTPClientOptions : NSObject <NSCopying>

@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSUInteger maxResponseBytes;
@property (nonatomic, assign) BOOL allowHTTP;
@property (nonatomic, assign) BOOL allowPrivateHosts;
@property (nonatomic, assign) BOOL followRedirects;

+ (instancetype)defaultOptions;

@end

@interface ATProtoSafeHTTPClient : NSObject

+ (instancetype)sharedClient;

+ (BOOL)validateURL:(NSURL *)url
            options:(nullable ATProtoSafeHTTPClientOptions *)options
              error:(NSError **)error;

- (void)performSafeDataTaskWithRequest:(NSURLRequest *)request
                    options:(nullable ATProtoSafeHTTPClientOptions *)options
                 completion:(void (^)(NSData * _Nullable data,
                                      NSHTTPURLResponse * _Nullable response,
                                      NSError * _Nullable error))completion;

- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    options:(nullable ATProtoSafeHTTPClientOptions *)options
                                   response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

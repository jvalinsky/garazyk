// NSURLSession compatibility layer for GNUstep
// Uses NSURLConnection internally
#ifndef NSURLSESSIONCOMPAT_H
#define NSURLSESSIONCOMPAT_H

#import <Foundation/Foundation.h>

#ifdef GNUSTEP

typedef void (^NSURLSessionDataTaskCompletionHandler)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error);

@class NSURLSessionConfiguration;
@class NSURLSessionDataTask;
@class NSURLSession;

@interface NSURLSessionConfiguration : NSObject
@property (nonatomic) NSTimeInterval timeoutIntervalForRequest;
@property (nonatomic) NSTimeInterval timeoutIntervalForResource;
@property (nonatomic, copy) NSDictionary *HTTPAdditionalHeaders;
+ (NSURLSessionConfiguration *)defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration;
@end

@interface NSURLSessionTask : NSObject
@property (readonly) NSURLRequest *originalRequest;
@property (readonly) NSURLResponse *response;
@property (readonly) NSError *error;
- (void)cancel;
- (void)resume;
@end

@interface NSURLSessionDataTask : NSURLSessionTask
@end

@interface NSURLSession : NSObject
@property (readonly) NSURLSessionConfiguration *configuration;
+ (NSURLSession *)sharedSession;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(NSURLSessionDataTaskCompletionHandler)completionHandler;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(NSURLSessionDataTaskCompletionHandler)completionHandler;
@end

#endif // GNUSTEP

#endif // NSURLSESSIONCOMPAT_H

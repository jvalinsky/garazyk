#import <Foundation/Foundation.h>

@class HttpRequest;

NS_ASSUME_NONNULL_BEGIN

@interface UIAuthManager : NSObject

- (instancetype)initWithPassword:(NSString *)password;

- (BOOL)validatePassword:(NSString *)password;
- (NSString *)createSessionToken;
- (void)invalidateSessionToken:(NSString *)token;
- (BOOL)isAuthorizedRequest:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END


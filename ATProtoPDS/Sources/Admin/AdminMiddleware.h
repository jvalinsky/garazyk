#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const AdminMiddlewareErrorDomain;

typedef NS_ENUM(NSInteger, AdminMiddlewareError) {
    AdminMiddlewareErrorNoAuthHeader = 1000,
    AdminMiddlewareErrorInvalidToken,
    AdminMiddlewareErrorNotAdmin,
    AdminMiddlewareErrorSessionExpired
};

@class HttpRequest;
@class HttpResponse;
@class Session;

typedef BOOL (^AdminAuthCheckBlock)(Session *session);

@interface AdminMiddleware : NSObject

@property (nonatomic, copy, nullable) AdminAuthCheckBlock customAdminCheck;

+ (instancetype)sharedMiddleware;

- (BOOL)verifyAdminAccessForRequest:(HttpRequest *)request
                           response:(HttpResponse *)response
                              error:(NSError **)error;

- (nullable Session *)extractSessionFromRequest:(HttpRequest *)request
                                        error:(NSError **)error;

- (void)setAdminDids:(NSArray<NSString *> *)adminDids;

@end

NS_ASSUME_NONNULL_END

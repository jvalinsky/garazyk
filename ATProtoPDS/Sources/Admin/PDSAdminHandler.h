#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PDSHTTPMethod) {
    PDSHTTPMethodDELETE,
    PDSHTTPMethodGET,
    PDSHTTPMethodPOST,
    PDSHTTPMethodPUT
};

@interface PDSAdminHandler : NSObject

+ (instancetype)sharedHandler;

- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                        path:(NSString *)path
                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                        body:(nullable NSData *)body;

@end

NS_ASSUME_NONNULL_END
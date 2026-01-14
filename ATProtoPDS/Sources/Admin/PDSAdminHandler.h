/*!
 @file PDSAdminHandler.h

 @abstract HTTP request handler for admin endpoints.

 @discussion Routes admin API requests to appropriate services.
 Handles account management, moderation, and server configuration.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @enum PDSHTTPMethod

 @abstract HTTP method types.

 @constant PDSHTTPMethodDELETE HTTP DELETE method.
 @constant PDSHTTPMethodGET HTTP GET method.
 @constant PDSHTTPMethodPOST HTTP POST method.
 @constant PDSHTTPMethodPUT HTTP PUT method.
 */
typedef NS_ENUM(NSInteger, PDSHTTPMethod) {
    PDSHTTPMethodDELETE,
    PDSHTTPMethodGET,
    PDSHTTPMethodPOST,
    PDSHTTPMethodPUT
};

/*!
 @class PDSAdminHandler

 @abstract Handles admin HTTP requests.
 */
@interface PDSAdminHandler : NSObject

/*! Returns the shared handler instance. */
+ (instancetype)sharedHandler;

/*! Handles an admin request and returns a response. */
- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                        path:(NSString *)path
                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                        body:(nullable NSData *)body;

@end

NS_ASSUME_NONNULL_END
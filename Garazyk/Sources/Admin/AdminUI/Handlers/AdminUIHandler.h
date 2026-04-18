#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AdminUIHTTPMethod) {
    AdminUIHTTPMethodGET,
    AdminUIHTTPMethodPOST,
    AdminUIHTTPMethodPUT,
    AdminUIHTTPMethodDELETE
};

/**
 * @class AdminUIHandler
 * @brief HTTP request handler for the AdminUI static assets and partials.
 *
 * This handler serves the AdminUI static files (HTML, CSS, JS) and generates
 * partial HTML responses for HTMX-based dynamic content loading.
 */
@interface AdminUIHandler : NSObject

/**
 * @brief Returns the shared singleton instance.
 *
 * @return The shared AdminUIHandler instance.
 */
+ (instancetype)sharedHandler;

/**
 * @brief Processes an AdminUI HTTP request.
 *
 * @param method The HTTP method.
 * @param path The request path.
 * @param headers HTTP request headers.
 * @param body Optional request body.
 * @param statusCode Output parameter for HTTP status code.
 * @param contentType Output parameter for Content-Type header.
 * @return The response body, or nil if path is not recognized.
 */
- (nullable NSString *)handleRequestWithMethod:(AdminUIHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

/**
 * @brief Gets the directory path for AdminUI assets.
 *
 * @return The absolute path to the AdminUI Assets directory.
 */
- (NSString *)assetsDirectoryPath;

/**
 * @brief Gets the directory path for AdminUI templates.
 *
 * @return The absolute path to the AdminUI Templates directory.
 */
- (NSString *)templatesDirectoryPath;

@end

NS_ASSUME_NONNULL_END

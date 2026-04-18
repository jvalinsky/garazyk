#import <Foundation/Foundation.h>
#import "PDSSequencerHealthHandler.h"
#import "PDSBlobAuditHandler.h"
#import "PDSRateLimitAdminHandler.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSSystemDiagnosticsHandler
 * @brief Coordinator for all system diagnostics API endpoints.
 *
 * Manages Sequencer Health, Blob Audits, and Rate Limit management
 * diagnostics through delegated handlers.
 */
@interface PDSSystemDiagnosticsHandler : NSObject

/**
 * @brief Returns the shared singleton instance.
 *
 * @return The shared PDSSystemDiagnosticsHandler instance.
 */
+ (instancetype)sharedHandler;

/**
 * @brief Processes diagnostics API requests.
 *
 * Routes to feature-specific handlers based on path:
 * - /admin/api/diagnostics/sequencer/* → PDSSequencerHealthHandler
 * - /admin/api/diagnostics/blobs/* → PDSBlobAuditHandler
 * - /admin/api/diagnostics/ratelimits/* → PDSRateLimitAdminHandler
 *
 * @param method HTTP method
 * @param path Request path
 * @param headers HTTP headers
 * @param body Request body
 * @param statusCode Output status code
 * @param contentType Output content type
 * @return Response body as JSON string or error response
 */
- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

@end

NS_ASSUME_NONNULL_END

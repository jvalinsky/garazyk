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

#pragma mark - Partials

- (NSString *)renderOverviewPartialWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderUsersPartialWithStatusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderUsersSearchWithQuery:(NSString *)query
                            statusCode:(nullable NSInteger *)statusCode
                           contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderInvitesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                    contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderIdentityPartialWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderHealthPartialWithStatusCode:(nullable NSInteger *)statusCode
                                   contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderHealthStatusWithStatusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderPLCLookupPartialWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderPLCExportPartialWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderPLCMetricsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderRelayUpstreamsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                          contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderRelayEventsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderRelayCrawlPartialWithStatusCode:(nullable NSInteger *)statusCode
                                       contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderAppViewBackfillPartialWithStatusCode:(nullable NSInteger *)statusCode
                                           contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderAppViewIndexPartialWithStatusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderAppViewMetricsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                          contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatConvosPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatConvosSearchWithQuery:(NSString *)query
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatGroupsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatGroupsSearchWithQuery:(NSString *)query
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatGroupDetailPartialWithGroupUri:(NSString *)groupUri
                                          statusCode:(nullable NSInteger *)statusCode
                                         contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatInviteLinksPartialWithStatusCode:(nullable NSInteger *)statusCode
                                           contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatInviteLinksSearchWithQuery:(NSString *)query
                                    statusCode:(nullable NSInteger *)statusCode
                                   contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatMessagesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatReportsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderChatReportsListWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneEventsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                         contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneStatusesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                           contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneTeamPartialWithStatusCode:(nullable NSInteger *)statusCode
                                       contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneTemplatesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                            contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneSetsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                       contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneCorrelationsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                               contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneVerificationPartialWithStatusCode:(nullable NSInteger *)statusCode
                                               contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderOzoneCorrelationsSearchWithDid:(NSString *)did
                                         statusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderSecuritySessionsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                               contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderSecurityAppPasswordsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                                 contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderSecuritySessionsListPartialWithParams:(NSDictionary *)params
                                              statusCode:(nullable NSInteger *)statusCode
                                             contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderSecurityAppPasswordsListPartialWithParams:(NSDictionary *)params
                                                 statusCode:(nullable NSInteger *)statusCode
                                                contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderDiagnosticsOverviewPartialWithStatusCode:(nullable NSInteger *)statusCode
                                               contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderDiagnosticsSequencerPartialWithStatusCode:(nullable NSInteger *)statusCode
                                                 contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderDiagnosticsBlobsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                             contentType:(NSString * _Nullable * _Nullable)contentType;

- (NSString *)renderDiagnosticsRateLimitsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                                  contentType:(NSString * _Nullable * _Nullable)contentType;

@end

NS_ASSUME_NONNULL_END

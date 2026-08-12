// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @category Authorization
 * @abstract Implements the PAR-only authorization, consent, and password sign-in HTTP flows.
 */
@interface ATProtoOAuth2Handler (Authorization)
/**
 * @abstract Validates a pushed authorization request and renders its consent page.
 * @discussion Direct authorization parameters are rejected: the request must contain only a
 * consumable PAR `request_uri` and optional matching client identifier. The method validates the
 * resolved client, redirect URI, state, and PKCE requirement before rendering the page. It writes
 * a JSON OAuth error for invalid input or client-validation failure; successful rendering creates
 * a CSRF cookie on the response.
 * @param request The GET authorization request containing the PAR reference.
 * @param response The response populated with the consent page or an OAuth error.
 */
- (void)handleAuthorizeRequest:(ATProtoHttpRequest *)request
                      response:(ATProtoHttpResponse *)response;
/**
 * @abstract Consumes an authorization consent decision and completes or rejects the OAuth flow.
 * @discussion The form input is untrusted. A denial removes the supplied pending-consent token and
 * redirects only after revalidating the client redirect URI. Approval requires a nonexpired
 * pending-consent token, removes it before issuing the authorization response, and revalidates the
 * client and redirect URI. Thus a token cannot be reused after either a successful approval or a
 * denial that supplies it.
 * @param request The form submission containing the consent decision and authorization parameters.
 * @param response The response populated with a validated redirect or an OAuth error.
 */
- (void)handleAuthorizeConfirm:(ATProtoHttpRequest *)request
                      response:(ATProtoHttpResponse *)response;
/**
 * @abstract Authenticates a password sign-in for a pending consent flow.
 * @discussion Requires a matching `X-CSRF-Token` header and `csrf_token` cookie, compared in
 * constant time, before passing the submitted handle and password to the account service. On
 * success it creates an in-memory, expiring pending-consent session and returns its opaque token
 * in JSON; it never writes the password to that session. Invalid CSRF input, credentials, or
 * service configuration are reported in the response.
 * @param request The form submission containing credentials and the CSRF token.
 * @param response The JSON success or failure response.
 */
- (void)handleAuthorizeSignIn:(ATProtoHttpRequest *)request
                     response:(ATProtoHttpResponse *)response;
/**
 * @abstract Renders the authorization HTML with validated request and client values.
 * @discussion Reads the authorization template from the configured asset path, HTML-escapes every
 * value inserted into the template, and issues an HttpOnly, SameSite=Strict CSRF cookie scoped to
 * `/oauth`. A missing or unreadable template produces an HTTP 500 response.
 * @param response The response populated with HTML, the CSRF cookie, or an asset failure.
 * @param params Validated authorization parameters to interpolate into the template.
 * @param client Validated client metadata used for the consent display.
 */
- (void)serveAuthorizePage:(ATProtoHttpResponse *)response
                    params:(NSDictionary *)params
                    client:(NSDictionary *)client;
@end

NS_ASSUME_NONNULL_END

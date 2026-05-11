// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file OAuthDemoHandler.h
 
 @abstract HTTP handler for the embedded OAuth demo UI.
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

@class HttpRequest;
@class HttpResponse;
NS_ASSUME_NONNULL_BEGIN

@class PDSController;

/*!
 @class OAuthDemoHandler

 @abstract Serves OAuth demo assets and route responses.

 @discussion Handles `/oauth-demo` requests and maps them to static assets
 bundled with the application.
 */
@interface OAuthDemoHandler : NSObject

/*!
 @method sharedHandler

 @abstract Returns the process-wide OAuth demo handler instance.
 */
+ (instancetype)sharedHandler;

/*!
 @method setDataDirectory:

 @abstract Sets the data directory used when resolving demo assets.

 @param dataDirectory Absolute path to the server data directory.
 */
- (void)setDataDirectory:(NSString *)dataDirectory;

/*!
 @method setController:

 @abstract Legacy API for wiring data-directory context from PDSController.

 @param controller Controller providing the active data directory.
 */
- (void)setController:(PDSController *)controller
    DEPRECATED_MSG_ATTRIBUTE("Use setDataDirectory: instead");

/*!
 @method canHandleRequest:

 @abstract Returns whether the request path belongs to the OAuth demo routes.

 @param request Incoming HTTP request.
 @result YES when the path starts with `/oauth-demo`, otherwise NO.
 */
- (BOOL)canHandleRequest:(HttpRequest *)request;

/*!
 @method handleRequest:response:

 @abstract Serves an OAuth demo asset or JSON error response.

 @param request Incoming HTTP request.
 @param response Response object to populate.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END

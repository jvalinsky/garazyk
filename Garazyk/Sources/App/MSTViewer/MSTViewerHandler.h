#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSController;
@class HttpRequest;
@class HttpResponse;

/*!
 @header MSTViewerHandler.h

 @abstract HTTP request handler for MST visualization interface.

 @discussion This handler provides a web-based GUI for exploring Merkle
 Search Tree structures in PDS repositories. Serves static assets (HTML/CSS/JS)
 and API endpoints for retrieving tree data, statistics, and exports.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!
 @class MSTViewerHandler

 @abstract Singleton handler for MST viewer HTTP requests.

 @discussion The MST viewer provides:
 - Interactive D3.js tree visualization
 - Hierarchical list view
 - Tree statistics (node count, depth, balance)
 - Export functionality (JSON, DOT, SVG)

 All requests to /mst-viewer and /api/mst are routed through this handler.
 */
@interface MSTViewerHandler : NSObject

/*!
 @method sharedHandler

 @abstract Returns the shared singleton instance.

 @return The shared MSTViewerHandler instance.
 */
+ (instancetype)sharedHandler;

/*!
 @method setController:

 @abstract Sets the PDS controller reference for database access.

 @param controller The PDSController instance.
 */
- (void)setController:(PDSController *)controller;

/*!
 @method canHandleRequest:

 @abstract Checks if this handler can handle the given request.

 @discussion Returns YES for paths starting with /mst-viewer or /api/mst.

 @param request The HTTP request.
 @return YES if this handler should process the request, NO otherwise.
 */
- (BOOL)canHandleRequest:(HttpRequest *)request;

/*!
 @method handleRequest:response:

 @abstract Processes an HTTP request and generates a response.

 @discussion Routes the request to either asset serving or API endpoints
 based on the path. Assets include HTML, CSS, and JavaScript files.
 API endpoints return JSON data.

 @param request The HTTP request.
 @param response The HTTP response to populate.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END

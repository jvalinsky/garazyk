// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSHttpMSTViewerRoutePack.m

 @abstract Registers HTTP routes for MST viewer pages and related inspection endpoints.

 @discussion Wires MST viewer route handlers into the HTTP server namespace so runtime components can render and serve MST inspection content. This file defines route exposure and registration flow, not MST business processing internals.
 */

#import "Network/PDSHttpMSTViewerRoutePack.h"

#import "App/MSTViewer/MSTViewerHandler.h"
#import "App/PDSController.h"
#import "Debug/GZLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpMSTViewerRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                      controller:(nullable PDSController *)controller {
  if (!controller) {
    GZ_LOG_WARN(@"PDSHttpMSTViewerRoutePack: MST Viewer routes not registered - "
                 @"missing controller");
    return;
  }

  MSTViewerHandler *mstViewerHandler = [MSTViewerHandler sharedHandler];
  [mstViewerHandler setController:controller];

  [server addHandlerForPath:@"/mst-viewer"
                    handler:^(HttpRequest *request, HttpResponse *response) {
                      [mstViewerHandler handleRequest:request response:response];
                    }];

  [server addHandlerForPath:@"/api/mst"
                    handler:^(HttpRequest *request, HttpResponse *response) {
                      [mstViewerHandler handleRequest:request response:response];
                    }];

  GZ_LOG_DEBUG(@"PDSHttpMSTViewerRoutePack: MST Viewer routes registered");
}

@end

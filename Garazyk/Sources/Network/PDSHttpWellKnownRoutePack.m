// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSHttpWellKnownRoutePack.m

 @abstract Registers well-known HTTP routes for discovery and protocol metadata exposure.

 @discussion Adds standardized well-known endpoint paths used by clients and federated services for discovery. Focuses on route registration and dispatch wiring, leaving payload generation to handlers.
 */

#import "Network/PDSHttpWellKnownRoutePack.h"

#import "App/PDSConfiguration.h"
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation PDSHttpWellKnownRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                      controller:(nullable PDSController *)controller
                   configuration:(nullable PDSConfiguration *)configuration
                  setCorsHeaders:(PDSHttpSetCorsHeadersBlock)setCorsHeaders {
  __weak PDSServiceDatabases *weakServiceDatabases = serviceDatabases;
  __weak PDSController *weakController = controller;
  __weak PDSConfiguration *weakConfiguration = configuration;

  NSString *_Nullable (^normalizedHostFromHostHeader)(NSString *_Nullable) =
      ^NSString *_Nullable(NSString *_Nullable hostHeader) {
        if (![hostHeader isKindOfClass:[NSString class]]) {
          return nil;
        }

        NSString *host = [hostHeader
            stringByTrimmingCharactersInSet:[NSCharacterSet
                                                whitespaceAndNewlineCharacterSet]];
        if (host.length == 0) {
          return nil;
        }

        while ([host hasSuffix:@"."] && host.length > 1) {
          host = [host substringToIndex:host.length - 1];
        }

        if ([host hasPrefix:@"["]) {
          NSRange closingBracket = [host rangeOfString:@"]"];
          if (closingBracket.location != NSNotFound &&
              closingBracket.location > 1) {
            host = [host substringWithRange:NSMakeRange(1,
                                                        closingBracket.location - 1)];
          }
        } else {
          NSRange lastColon =
              [host rangeOfString:@":" options:NSBackwardsSearch];
          if (lastColon.location != NSNotFound) {
            if ([host rangeOfString:@":"
                            options:0
                              range:NSMakeRange(0, lastColon.location)]
                    .location == NSNotFound) {
              host = [host substringToIndex:lastColon.location];
            }
          }
        }

        host = [ATProtoHandleValidator normalizeHandle:host];
        return host.length > 0 ? host : nil;
      };

  BOOL (^hostMatchesAllowedDomains)(NSString *host,
                                    NSArray<NSString *> *allowedDomains) =
      ^BOOL(NSString *host, NSArray<NSString *> *allowedDomains) {
        if (allowedDomains.count == 0) {
          return YES;
        }

        for (NSString *domain in allowedDomains) {
          NSString *normalizedDomain =
              [normalizedHostFromHostHeader(domain) ?: @"" copy];
          if (normalizedDomain.length == 0) {
            continue;
          }
          if ([host isEqualToString:normalizedDomain]) {
            return YES;
          }
          NSString *suffix = [@"." stringByAppendingString:normalizedDomain];
          if ([host hasSuffix:suffix]) {
            return YES;
          }
        }
        return NO;
      };

  void (^handleWellKnownAtprotoDid)(HttpRequest *request,
                                    HttpResponse *response,
                                    BOOL includeBody) =
      ^(HttpRequest *request, HttpResponse *response, BOOL includeBody) {
        NSString *hostHeader = [request headerForKey:@"Host"];
        NSString *handle = normalizedHostFromHostHeader(hostHeader);

        if (handle.length == 0) {
          response.statusCode = HttpStatusBadRequest;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"missing host header\n"];
          }
          return;
        }

        PDSConfiguration *config = weakConfiguration;
        NSArray<NSString *> *allowedDomains =
            config.availableUserDomains ?: @[];
        if (!hostMatchesAllowedDomains(handle, allowedDomains)) {
          response.statusCode = HttpStatusNotFound;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"not found\n"];
          }
          return;
        }

        PDSServiceDatabases *strongServiceDatabases = weakServiceDatabases;
        if (!strongServiceDatabases) {
          PDSController *strongController = weakController;
          strongServiceDatabases = strongController.serviceDatabases;
        }

        if (!strongServiceDatabases) {
          response.statusCode = HttpStatusInternalServerError;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"internal error\n"];
          }
          return;
        }

        NSError *dbError = nil;
        PDSDatabaseAccount *account =
            [strongServiceDatabases getAccountByHandle:handle error:&dbError];
        if (dbError) {
          PDS_LOG_ERROR(@"Database error looking up handle %@: %@", handle,
                        dbError.localizedDescription ?: @"unknown error");
          response.statusCode = HttpStatusInternalServerError;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"internal error\n"];
          }
          return;
        }

        if (!account || account.did.length == 0) {
          response.statusCode = HttpStatusNotFound;
          response.contentType = @"text/plain; charset=utf-8";
          if (includeBody) {
            [response setBodyString:@"not found\n"];
          }
          return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"text/plain; charset=utf-8";
        [response setHeader:@"Host" forKey:@"Vary"];
        [response setHeader:@"max-age=300" forKey:@"Cache-Control"];
        if (includeBody) {
          [response setBodyString:[account.did stringByAppendingString:@"\n"]];
        }
      };

  [server addHandlerForPath:@"/.well-known/atproto-did"
                    handler:^(HttpRequest *request, HttpResponse *response) {
                      setCorsHeaders(response, request);
                      NSString *method = request.methodString.uppercaseString;
                      if ([method isEqualToString:@"OPTIONS"]) {
                        response.statusCode = HttpStatusOK;
                      } else {
                        handleWellKnownAtprotoDid(
                            request, response, [method isEqualToString:@"GET"]);
                      }
                    }];

  PDS_LOG_DEBUG(@"PDSHttpWellKnownRoutePack: .well-known routes registered");
}

@end


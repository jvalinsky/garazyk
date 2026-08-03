// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpWellKnownRoutePack.m

 @abstract Registers well-known HTTP routes for discovery and protocol metadata exposure.

 @discussion Adds standardized well-known endpoint paths used by clients and federated services for discovery. Focuses on route registration and dispatch wiring, leaving payload generation to handlers.
 */

#import "Network/ATProtoHttpWellKnownRoutePack.h"

#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSController.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Services/PDS/PDSRASLResolver.h"

@implementation ATProtoHttpWellKnownRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                      controller:(nullable PDSController *)controller
                   configuration:(nullable ATProtoServiceConfiguration *)configuration
                  setCorsHeaders:(ATProtoHttpSetCorsHeadersBlock)setCorsHeaders {
  __weak PDSServiceDatabases *weakServiceDatabases = serviceDatabases;
  __weak PDSController *weakController = controller;
  __weak ATProtoServiceConfiguration *weakConfiguration = configuration;

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

        ATProtoServiceConfiguration *config = weakConfiguration;
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
          GZ_LOG_ERROR(@"Database error looking up handle %@: %@", handle,
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

  // RASL (https://dasl.ing/rasl.html): "GET or HEAD", "stateless (no cookies,
  // no credentials of any kind), and ... no content negotiation". This route
  // sets neither cookies nor Vary, and always answers application/octet-stream
  // regardless of any stored content type, per spec.
  //
  // CID -> bytes resolution is a bounded scan across locally known accounts'
  // block and blob stores (see PDSRASLResolver) — Garazyk has no host-wide
  // CID index today. See workstream 10 Phase 5 for the design tradeoff.
  void (^handleWellKnownRasl)(HttpRequest *request, HttpResponse *response, BOOL includeBody) =
      ^(HttpRequest *request, HttpResponse *response, BOOL includeBody) {
        NSString *cidParam = [request.pathParameters[@"cid"] stringByRemovingPercentEncoding];
        CID *cid = cidParam.length > 0
            ? [CID daslCIDFromString:cidParam profile:ATProtoDASLCIDProfileBig]
            : nil;
        if (!cid) {
          response.statusCode = HttpStatusBadRequest;
          response.contentType = @"application/octet-stream";
          return;
        }

        PDSController *strongController = weakController;
        if (!strongController.userDatabasePool || !strongController.blobService ||
            !strongController.accountService) {
          response.statusCode = HttpStatusInternalServerError;
          response.contentType = @"application/octet-stream";
          return;
        }

        PDSRASLResolver *resolver =
            [[PDSRASLResolver alloc] initWithDatabasePool:strongController.userDatabasePool
                                                blobService:strongController.blobService
                                              accountService:strongController.accountService];
        NSData *data = [resolver dataForCID:cid maxAccountsToScan:200];
        if (!data) {
          response.statusCode = HttpStatusNotFound;
          response.contentType = @"application/octet-stream";
          return;
        }

        // Defense in depth: re-verify against the CID's own digest before
        // serving, rather than trusting that whatever the resolver found was
        // stored correctly. Only SHA-256 (base DASL) is checked here; BLAKE3
        // (Big DASL) verification lands with the Phase 6 streaming verifier —
        // nothing writes a BLAKE3-addressed block or blob today, so this scan
        // should never actually surface one, but if it somehow did, this
        // route serves it unverified rather than failing closed. Tightening
        // that (reject non-SHA-256 CIDs outright here) is a one-line follow-up
        // once Phase 6 lands and can be exercised by a real test fixture.
        NSData *multihash = cid.multihash;
        if (multihash.length >= 2) {
          const uint8_t *multihashBytes = multihash.bytes;
          if (multihashBytes[0] == ATProtoDASLMultihashSHA256) {
            NSData *expectedDigest = [multihash subdataWithRange:NSMakeRange(2, multihash.length - 2)];
            NSData *actualDigest = [CID sha256Digest:data];
            if (![actualDigest isEqualToData:expectedDigest]) {
              response.statusCode = HttpStatusInternalServerError;
              response.contentType = @"application/octet-stream";
              return;
            }
          }
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/octet-stream";
        if (includeBody) {
          [response setBodyData:data];
        }
      };

  [server addRoute:@"GET" path:@"/.well-known/rasl/:cid"
           handler:^(HttpRequest *request, HttpResponse *response) {
             handleWellKnownRasl(request, response, YES);
           }];
  [server addRoute:@"HEAD" path:@"/.well-known/rasl/:cid"
           handler:^(HttpRequest *request, HttpResponse *response) {
             handleWellKnownRasl(request, response, NO);
           }];

  GZ_LOG_DEBUG(@"ATProtoHttpWellKnownRoutePack: .well-known routes registered");
}

@end


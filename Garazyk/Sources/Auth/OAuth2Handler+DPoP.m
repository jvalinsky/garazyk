// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+DPoP.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (DPoP)

#pragma mark - Forwarded Header Trust
- (BOOL)requestShouldTrustForwardedHeaders:(HttpRequest *)request {
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *rawTrustProxy = [env[@"PDS_TRUST_PROXY_HEADERS"] lowercaseString];
  BOOL trustProxy = [rawTrustProxy isEqualToString:@"1"] ||
                    [rawTrustProxy isEqualToString:@"true"] ||
                    [rawTrustProxy isEqualToString:@"yes"] ||
                    [rawTrustProxy isEqualToString:@"on"];
  if (!trustProxy) {
    return NO;
  }

  NSString *remote = [[request.remoteAddress ?: @"" lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (remote.length == 0) {
    return NO;
  }
  if ([remote hasPrefix:@"127."] || [remote isEqualToString:@"::1"] ||
      [remote isEqualToString:@"localhost"]) {
    return YES;
  }
  if ([remote hasPrefix:@"10."] || [remote hasPrefix:@"192.168."]) {
    return YES;
  }
  if ([remote hasPrefix:@"172."]) {
    NSArray<NSString *> *parts = [remote componentsSeparatedByString:@"."];
    if (parts.count >= 2) {
      NSInteger secondOctet = [parts[1] integerValue];
      if (secondOctet >= 16 && secondOctet <= 31) {
        return YES;
      }
    }
  }
  return NO;
}

#pragma mark - DPoP & Request Origin Helpers
- (NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request {
  NSString *path = request.path ?: @"/";
  NSString *hostHeader = [[request headerForKey:@"host"]
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  NSString *hostLower = [hostHeader lowercaseString];
  BOOL localHostHeader = [hostLower containsString:@"localhost"] ||
                         [hostLower hasPrefix:@"127.0.0.1"] ||
                         [hostLower hasPrefix:@"[::1]"] ||
                         [hostLower isEqualToString:@"::1"];
  BOOL trustedForwarded = [self requestShouldTrustForwardedHeaders:request];

  NSString *scheme = nil;
  if (trustedForwarded) {
    NSString *forwardedProto =
        [[request headerForKey:@"x-forwarded-proto"] lowercaseString];
    if (forwardedProto.length > 0) {
      NSString *firstProto =
          [[forwardedProto componentsSeparatedByString:@","] firstObject];
      firstProto =
          [firstProto stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([firstProto isEqualToString:@"https"] ||
          [firstProto isEqualToString:@"http"]) {
        scheme = firstProto;
      }
    }
  }

  NSURL *issuerURL = [NSURL URLWithString:self.oauthServer.issuer ?: @""];
  if (scheme.length == 0) {
    if (localHostHeader) {
      scheme = @"http";
    } else if (issuerURL.scheme.length > 0) {
      scheme = issuerURL.scheme;
    } else {
      scheme = @"https";
    }
  }

  NSString *authority = nil;
  if (hostHeader.length > 0 && (trustedForwarded || localHostHeader)) {
    authority = hostHeader;
  } else if (issuerURL.host.length > 0) {
    authority = issuerURL.host;
    if (issuerURL.port != nil) {
      BOOL isDefaultPort =
          ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] &&
           issuerURL.port.integerValue == 443) ||
          ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] &&
           issuerURL.port.integerValue == 80);
      if (!isDefaultPort) {
        authority = [NSString
            stringWithFormat:@"%@:%@", issuerURL.host, issuerURL.port];
      }
    }
  }

  if (authority.length == 0) {
    return nil;
  }

  NSMutableString *urlString =
      [NSMutableString stringWithFormat:@"%@://%@%@", scheme, authority, path];
  if (request.queryString.length > 0) {
    [urlString appendFormat:@"?%@", request.queryString];
  }
  return [NSURL URLWithString:urlString];
}

- (NSString *)requestOriginForRequest:(HttpRequest *)request {
  NSString *hostHeader = [[request headerForKey:@"host"]
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  NSString *hostLower = [hostHeader lowercaseString];
  BOOL localHostHeader = [hostLower containsString:@"localhost"] ||
                         [hostLower hasPrefix:@"127.0.0.1"] ||
                         [hostLower hasPrefix:@"[::1]"] ||
                         [hostLower isEqualToString:@"::1"];
  BOOL trustedForwarded = [self requestShouldTrustForwardedHeaders:request];

  NSString *scheme = nil;
  if (trustedForwarded) {
    NSString *forwardedProto =
        [[request headerForKey:@"x-forwarded-proto"] lowercaseString];
    if (forwardedProto.length > 0) {
      NSString *firstProto =
          [[forwardedProto componentsSeparatedByString:@","] firstObject];
      firstProto =
          [firstProto stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([firstProto isEqualToString:@"https"] ||
          [firstProto isEqualToString:@"http"]) {
        scheme = firstProto;
      }
    }
  }

  NSURL *issuerURL = [NSURL URLWithString:self.oauthServer.issuer ?: @""];
  if (scheme.length == 0) {
    if (localHostHeader) {
      scheme = @"http";
    } else if (issuerURL.scheme.length > 0) {
      scheme = issuerURL.scheme;
    } else {
      scheme = @"https";
    }
  }

  NSString *authority = nil;
  if (hostHeader.length > 0 && (trustedForwarded || localHostHeader)) {
    authority = hostHeader;
  } else if (issuerURL.host.length > 0) {
    authority = issuerURL.host;
    if (issuerURL.port != nil) {
      BOOL isDefaultPort =
          ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] &&
           issuerURL.port.integerValue == 443) ||
          ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] &&
           issuerURL.port.integerValue == 80);
      if (!isDefaultPort) {
        authority = [NSString
            stringWithFormat:@"%@:%@", issuerURL.host, issuerURL.port];
      }
    }
  }

  if (authority.length == 0) {
    return self.oauthServer.issuer;
  }
  return [NSString stringWithFormat:@"%@://%@", scheme, authority];
}

#pragma mark - DPoP Validation
- (void)attachDPoPNonceToResponseIfMissing:(HttpResponse *)response {
  NSString *existingNonce = response.headers[@"DPoP-Nonce"] ?: response.headers[@"dpop-nonce"];
  if (existingNonce.length > 0) {
    return;
  }

  NSString *nextNonce = [[PDSNonceManager sharedManager] generateNonce];
  if (nextNonce.length > 0) {
    [response setHeader:nextNonce forKey:@"DPoP-Nonce"];
  }
}

- (BOOL)validateDPoPForRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
                 outThumbprint:(NSString **)outThumbprint {
  NSString *dpopProof = [request headerForKey:@"dpop"];
  if (!dpopProof || dpopProof.length == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing DPoP proof"
    }];
    return NO;
  }

  NSURL *dpopURL = [self expectedDPoPURLForRequest:request];
  if (!dpopURL) {
    GZ_LOG_AUTH_DEBUG(@"validateDPoPForRequest: Failed to construct DPoP URL");
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Unable to construct DPoP URL"
    }];
    return NO;
  }

  NSError *dpopError = nil;
  NSString *dpopThumbprint = nil;
  NSString *requestedNonce = [request headerForKey:@"DPoP-Nonce"];
  if (requestedNonce.length == 0) {
    requestedNonce = nil;
  }

  if (![OAuth2DPoPProof verifyProof:dpopProof
                             method:request.methodString
                                url:dpopURL
                              nonce:requestedNonce
                       requireNonce:YES
                      outThumbprint:&dpopThumbprint
                              error:&dpopError]) {
    if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
      NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
      if (nonce.length > 0) {
        [response setHeader:nonce forKey:@"DPoP-Nonce"];
      }
      [response setHeader:@"DPoP error=\"use_dpop_nonce\""
                   forKey:@"WWW-Authenticate"];
      [response setHeader:@"no-store" forKey:@"Cache-Control"];
      [response setHeader:@"no-cache" forKey:@"Pragma"];
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"use_dpop_nonce",
        @"error_description" : dpopError.localizedDescription
            ?: @"DPoP nonce required"
      }];
      return NO;
    }
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_dpop_proof",
      @"error_description" : dpopError.localizedDescription
          ?: @"Invalid DPoP proof"
    }];
    return NO;
  }

  [self attachDPoPNonceToResponseIfMissing:response];

  if (dpopThumbprint.length > 0) {
    NSString *prefix = dpopThumbprint.length > 8
                           ? [dpopThumbprint substringToIndex:8]
                           : dpopThumbprint;
    GZ_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint_prefix=%@)", prefix);
  } else {
    GZ_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint unavailable)");
  }

  if (outThumbprint) {
    *outThumbprint = dpopThumbprint;
  }
  return YES;
}

@end

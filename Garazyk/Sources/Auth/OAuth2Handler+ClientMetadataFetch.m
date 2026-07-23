// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+ClientMetadataFetch.h"
#import "Auth/OAuth2.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/SSRFValidator.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (ClientMetadataFetch)

- (NSDictionary *)parseClientMetadataFromInput:(id)clientMetadataInput {
  if ([clientMetadataInput isKindOfClass:[NSDictionary class]]) {
    return (NSDictionary *)clientMetadataInput;
  }

  if ([clientMetadataInput isKindOfClass:[NSString class]]) {
    NSString *clientMetadataString = (NSString *)clientMetadataInput;
    if (clientMetadataString.length == 0) {
      return nil;
    }

    NSData *jsonData =
        [clientMetadataString dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
      GZ_LOG_AUTH_WARN(@"Failed to decode client_metadata text as UTF-8");
      return nil;
    }

    NSError *jsonError = nil;
    id parsedJSON = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:0
                                                      error:&jsonError];
    if (jsonError) {
      GZ_LOG_AUTH_WARN(@"Failed to parse client_metadata JSON: %@",
                        jsonError.localizedDescription);
      return nil;
    }
    if (![parsedJSON isKindOfClass:[NSDictionary class]]) {
      GZ_LOG_AUTH_WARN(@"client_metadata is not a JSON object");
      return nil;
    }

    NSDictionary *clientMetadata = (NSDictionary *)parsedJSON;
    GZ_LOG_AUTH_INFO(@"Parsed client_metadata with %lu keys",
                      (unsigned long)clientMetadata.count);
    return clientMetadata;
  }

  return nil;
}

- (void)fetchClientMetadataFromURL:(NSString *)urlStr
                        completion:(void (^)(NSDictionary *_Nullable metadata,
                                             NSError *_Nullable error))completion {
  if (!completion)
    return;

  NSURL *url = [NSURL URLWithString:urlStr];
  NSString *host = url.host;

  if (!url || !host) {
    completion(nil, [NSError errorWithDomain:@"OAuth2"
                                        code:400
                                    userInfo:@{
                                      NSLocalizedDescriptionKey :
                                          @"Invalid client_id URL"
                                    }]);
    return;
  }

  GZ_LOG_AUTH_DEBUG(@"Fetching dynamic client metadata from %@", urlStr);

  // For E2E tests in Docker, we may need to map the client's public URL (e.g. localhost)
  // to an internal container name (e.g. oauth-client).
  NSString *effectiveUrlStr = urlStr;
  const char *envHostMap = getenv("GARAZYK_OAUTH_HOST_MAP");
  if (envHostMap) {
      NSString *hostMap = [NSString stringWithUTF8String:envHostMap];
      NSArray *parts = [hostMap componentsSeparatedByString:@"="];
      if (parts.count == 2) {
          effectiveUrlStr = [urlStr stringByReplacingOccurrencesOfString:parts[0]
                                                              withString:parts[1]];
          if (![effectiveUrlStr isEqualToString:urlStr]) {
              GZ_LOG_AUTH_DEBUG(@"Mapped OAuth client URL: %@ -> %@", urlStr, effectiveUrlStr);
          }
      }
  }

  NSURL *fetchUrl = [NSURL URLWithString:effectiveUrlStr];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:fetchUrl];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  request.timeoutInterval = 10.0;

  ATProtoSafeHTTPClientOptions *safeOptions = [[ATProtoSafeHTTPClientOptions alloc] init];
  safeOptions.timeout = 10.0;
  safeOptions.maxResponseBytes = 256 * 1024; // 256 KB
  
  // In development/test environments, we allow fetching metadata from local/private hosts.
  BOOL allowPrivate = NO;
  const char *envAllowPrivate = getenv("GARAZYK_ALLOW_PRIVATE_OAUTH_CLIENTS");
  if (envAllowPrivate && (strcmp(envAllowPrivate, "1") == 0 || strcmp(envAllowPrivate, "true") == 0)) {
    allowPrivate = YES;
  }
  
  safeOptions.allowHTTP = allowPrivate;
  safeOptions.allowPrivateHosts = allowPrivate;
  safeOptions.followRedirects = YES;

  [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                 options:safeOptions
                                              completion:^(NSData *data, NSHTTPURLResponse *httpResponse, NSError *err) {
    // Map ATProtoSafeHTTPClient SSRF errors to OAuth error codes
    if (err && [err.domain isEqualToString:ATProtoSafeHTTPClientErrorDomain]) {
      NSInteger oauthErrorCode = 500;
      NSString *oauthMessage = @"Failed to fetch client metadata";
      if (err.code == ATProtoSafeHTTPClientErrorSSRFBlocked) {
        oauthErrorCode = 403;
        oauthMessage = @"SSRF Protection: Host resolves to private IP address";
        GZ_LOG_AUTH_ERROR(@"Blocked SSRF attempt for dynamic discovery: %@", urlStr);
      } else if (err.code == ATProtoSafeHTTPClientErrorInvalidURL) {
        oauthErrorCode = 400;
        oauthMessage = @"Invalid client_id URL";
      } else if (err.code == ATProtoSafeHTTPClientErrorUnsupportedScheme) {
        oauthErrorCode = 400;
        oauthMessage = @"Only HTTPS is allowed for client metadata";
      } else if (err.code == ATProtoSafeHTTPClientErrorRedirectBlocked) {
        oauthErrorCode = 403;
        oauthMessage = @"SSRF Protection: Redirect target resolves to private IP address";
        GZ_LOG_AUTH_ERROR(@"Blocked SSRF redirect attempt for dynamic discovery: %@", urlStr);
      }
      NSError *oauthError = [NSError errorWithDomain:@"OAuth2"
                                                 code:oauthErrorCode
                                             userInfo:@{
                                               NSLocalizedDescriptionKey: oauthMessage,
                                               NSUnderlyingErrorKey: err
                                             }];
      completion(nil, oauthError);
      return;
    }

    if (err) {
      completion(nil, err);
      return;
    }

    if (httpResponse.statusCode == 200 && data) {
      NSError *jsonError = nil;
      id json = [NSJSONSerialization JSONObjectWithData:data
                                                  options:0
                                                    error:&jsonError];
      if ([json isKindOfClass:[NSDictionary class]]) {
        completion(json, nil);
      } else {
        completion(nil, jsonError ?: [NSError
                             errorWithDomain:@"OAuth2"
                                        code:400
                                    userInfo:@{
                                      NSLocalizedDescriptionKey :
                                          @"Client metadata is not a "
                                          @"JSON object"
                                    }]);
      }
    } else {
      completion(nil, [NSError
                          errorWithDomain:@"OAuth2"
                                     code:httpResponse.statusCode
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       [NSString
                                           stringWithFormat:
                                               @"Failed to fetch "
                                               @"client metadata: %ld",
                                               (long)httpResponse
                                                   .statusCode]
                                 }]);
    }
  }];
}

@end

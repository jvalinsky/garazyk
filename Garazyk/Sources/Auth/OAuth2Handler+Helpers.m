// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+Helpers.h"
#import "Auth/OAuth2.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@implementation OAuth2Handler (Helpers)

#pragma mark - JSON Parsing
- (NSDictionary *)parseJSONBody:(NSData *)data {
  if (!data || data.length == 0) {
    return nil;
  }

  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (!json || ![json isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  return (NSDictionary *)json;
}

#pragma mark - Form Parsing
- (NSDictionary *)parseFormUrlEncodedString:(NSString *)input {
  if (!input) {
    return @{};
  }
  NSMutableDictionary *params = [NSMutableDictionary dictionary];
  // In application/x-www-form-urlencoded format, '+' represents a space character.
  // We replace '+' with '%20' so NSURLComponents percent-decodes it to space.
  NSString *normalizedInput =
      [input stringByReplacingOccurrencesOfString:@"+" withString:@"%20"];
  NSURLComponents *components = [[NSURLComponents alloc] init];
  components.percentEncodedQuery = normalizedInput;

  for (NSURLQueryItem *item in components.queryItems) {
    if (item.name) {
      params[item.name] = item.value ?: @"";
    }
  }
  return [params copy];
}

#pragma mark - Date Helpers
- (NSString *)iso8601StringFromDate:(NSDate *)date {
  return [NSDateFormatter atproto_stringFromDate:date];
}

- (NSDate *)dateFromISO8601String:(NSString *)dateString {
  return [NSDateFormatter atproto_dateFromString:dateString];
}

#pragma mark - CORS
- (void)setCorsHeaders:(HttpResponse *)response forRequest:(HttpRequest *)request {
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSArray<NSString *> *allowedOrigins =
      [config arrayForKey:@"cors.allowed_origins"];
  if (!allowedOrigins) {
    allowedOrigins = @[ @"*" ];
  }

  NSString *origin = [request headerForKey: @"Origin"];
  BOOL isMetadataPath = [request.path hasPrefix: @"/.well-known/"];

  if (origin && ([allowedOrigins containsObject: @"*"] || [origin hasPrefix: @"http://127.0.0.1"] || [origin hasPrefix: @"http://localhost"])) {
    [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  } else if (isMetadataPath) {
    // Public metadata fallback
    [response setHeader: @"*" forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  } else if (origin && [allowedOrigins containsObject:origin]) {
    [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  } else if (!origin && [allowedOrigins containsObject: @"*"]) {
    [response setHeader: @"*" forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  }

  NSArray *methodsArr = [config arrayForKey:@"cors.allowed_methods"];
  NSString *allowedMethods = methodsArr ? [methodsArr componentsJoinedByString:@", "] : @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
  NSArray *headersArr = [config arrayForKey:@"cors.allowed_headers"];
  NSString *allowedHeaders = headersArr ? [headersArr componentsJoinedByString:@", "] : @"DPoP, Authorization, Content-Type, *";
  NSInteger maxAge = [config integerForKey:@"cors.max_age"] ?: 86400;

  [response setHeader:allowedMethods forKey:@"Access-Control-Allow-Methods"];
  [response setHeader:allowedHeaders forKey:@"Access-Control-Allow-Headers"];
  [response setHeader:[NSString stringWithFormat:@"%ld", (long)maxAge]
               forKey:@"Access-Control-Max-Age"];
  [response setHeader:@"DPoP-Nonce, WWW-Authenticate"
               forKey:@"Access-Control-Expose-Headers"];
  [response setHeader:@"Origin" forKey:@"Vary"];
}

@end

/*!
 @file HttpParsing.m

 @abstract Implements shared HTTP parsing helpers used by parser/session layers.

 @discussion Provides reusable parsing support routines for protocol components, including normalization and validation helpers. Serves parser infrastructure without owning connection or routing flow.
 */

#import "Network/HttpParsing.h"

@implementation HttpParsing

+ (NSDictionary<NSString *, id> *)parseQueryString:(NSString *)queryString {
  if (queryString.length == 0) {
    return @{};
  }

  NSMutableDictionary<NSString *, id> *params = [NSMutableDictionary dictionary];
  NSArray<NSString *> *pairs = [queryString componentsSeparatedByString:@"&"];

  for (NSString *pair in pairs) {
    NSRange eqRange = [pair rangeOfString:@"="];
    NSString *key;
    NSString *value;
    if (eqRange.location != NSNotFound) {
      key = [self urlDecode:[pair substringToIndex:eqRange.location]];
      value = [self urlDecode:[pair substringFromIndex:eqRange.location + 1]];
    } else {
      key = [self urlDecode:pair];
      value = @"";
    }

    id existing = params[key];
    if (existing) {
      if ([existing isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)existing addObject:value];
      } else {
        NSMutableArray *array =
            [NSMutableArray arrayWithObjects:existing, value, nil];
        params[key] = array;
      }
    } else {
      params[key] = value;
    }
  }

  return [params copy];
}

+ (NSString *)urlDecode:(NSString *)string {
  NSString *result =
      [string stringByReplacingOccurrencesOfString:@"+" withString:@" "];
  result = [result stringByRemovingPercentEncoding];
  return result ?: string;
}

+ (HttpMethod)methodFromString:(NSString *)string {
  if ([string isEqualToString:@"GET"])
    return HttpMethodGET;
  if ([string isEqualToString:@"POST"])
    return HttpMethodPOST;
  if ([string isEqualToString:@"PUT"])
    return HttpMethodPUT;
  if ([string isEqualToString:@"DELETE"])
    return HttpMethodDELETE;
  if ([string isEqualToString:@"PATCH"])
    return HttpMethodPATCH;
  if ([string isEqualToString:@"OPTIONS"])
    return HttpMethodOPTIONS;
  if ([string isEqualToString:@"HEAD"])
    return HttpMethodHEAD;
  return HttpMethodUnknown;
}

@end

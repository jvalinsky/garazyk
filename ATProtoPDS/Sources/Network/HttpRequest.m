#import "Network/HttpRequest.h"
#import <stdint.h>

@interface HttpRequest ()

@property(nonatomic, readwrite, copy) NSDictionary *jsonBody;
@property(nonatomic, readwrite, copy) NSDictionary *multipartFormData;
@property(nonatomic, readwrite, copy) NSString *remoteAddress;

@end

@implementation HttpRequest

+ (instancetype)requestWithData:(NSData *)data {
  return [[self alloc] parseFromData:data remoteAddress:nil];
}

+ (instancetype)requestWithData:(NSData *)data
                  remoteAddress:(NSString *)remoteAddress {
  return [[self alloc] parseFromData:data remoteAddress:remoteAddress];
}

- (instancetype)initWithMethod:(HttpMethod)method
                  methodString:(NSString *)methodString
                          path:(NSString *)path
                   queryString:(NSString *)queryString
                   queryParams:
                       (NSDictionary<NSString *, NSString *> *)queryParams
                       version:(NSString *)version
                       headers:(NSDictionary<NSString *, NSString *> *)headers
                          body:(NSData *)body
                 remoteAddress:(NSString *)remoteAddress {
  self = [super init];
  if (self) {
    _method = method;
    _methodString = [methodString copy];
    _path = [path copy];
    _queryString = [queryString copy];
    _queryParams = [queryParams copy];
    _version = [version copy];
    _headers = [self normalizeHeaders:headers];
    _body = [body copy];
    _remoteAddress = [remoteAddress copy];
    _correlationID = [headers[@"x-correlation-id"] ?: headers[@"x-request-id"] ?: [[NSUUID UUID] UUIDString] copy];
    _jsonBody = [self parseJsonBody:body];
    _multipartFormData = [self parseMultipartFormData:body headers:headers];
  }
  return self;
}

- (NSDictionary *)normalizeHeaders:(NSDictionary *)headers {
  if (!headers)
    return @{};
  NSMutableDictionary *normalized =
      [NSMutableDictionary dictionaryWithCapacity:headers.count];
  for (NSString *key in headers) {
    normalized[key.lowercaseString] = headers[key];
  }
  return [normalized copy];
}

- (NSDictionary *)parseJsonBody:(NSData *)body {
  if (!body || body.length == 0) {
    return nil;
  }

  NSError *error = nil;
  NSDictionary *json =
      [NSJSONSerialization JSONObjectWithData:body options:0 error:&error];
  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return json;
}

- (NSDictionary *)parseMultipartFormData:(NSData *)body
                                 headers:(NSDictionary *)headers {
  if (!body || body.length == 0) {
    return nil;
  }

  NSString *contentType = headers[@"content-type"] ?: headers[@"Content-Type"];
  if (!contentType || ![contentType hasPrefix:@"multipart/form-data"]) {
    return nil;
  }

  // Extract boundary from Content-Type header
  NSString *boundary = nil;
  NSArray *components = [contentType componentsSeparatedByString:@";"];
  for (NSString *component in components) {
    NSString *trimmed =
        [component stringByTrimmingCharactersInSet:[NSCharacterSet
                                                       whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"boundary="]) {
      boundary = [trimmed substringFromIndex:9];
      break;
    }
  }

  if (!boundary) {
    return nil;
  }

  // Convert boundary to data for binary search
  NSString *boundaryMarker = [NSString stringWithFormat:@"--%@", boundary];
  NSData *boundaryData =
      [boundaryMarker dataUsingEncoding:NSUTF8StringEncoding];
  NSData *crlfCrlfData = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];

  NSMutableDictionary *formData = [NSMutableDictionary dictionary];
  NSUInteger position = 0;

  while (position < body.length) {
    // Find next boundary
    NSRange boundaryRange =
        [body rangeOfData:boundaryData
                  options:0
                    range:NSMakeRange(position, body.length - position)];
    if (boundaryRange.location == NSNotFound) {
      break;
    }

    // Skip boundary line
    position = boundaryRange.location + boundaryRange.length;

    // Skip CRLF after boundary
    if (position + 2 <= body.length) {
      NSData *crlf = [body subdataWithRange:NSMakeRange(position, 2)];
      if ([crlf
              isEqualToData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]]) {
        position += 2;
      }
    }

    // Check for end boundary (--)
    if (position + 2 <= body.length) {
      NSData *endCheck = [body subdataWithRange:NSMakeRange(position, 2)];
      if ([endCheck
              isEqualToData:[@"--" dataUsingEncoding:NSUTF8StringEncoding]]) {
        break; // End of multipart data
      }
    }

    // Find headers/body separator
    NSRange separatorRange =
        [body rangeOfData:crlfCrlfData
                  options:0
                    range:NSMakeRange(position, body.length - position)];
    if (separatorRange.location == NSNotFound) {
      break;
    }

    // Parse headers
    NSUInteger headersStart = position;
    NSUInteger headersEnd = separatorRange.location;
    NSData *headersData = [body
        subdataWithRange:NSMakeRange(headersStart, headersEnd - headersStart)];
    NSString *headersString =
        [[NSString alloc] initWithData:headersData
                              encoding:NSUTF8StringEncoding];

    // Parse Content-Disposition
    NSString *fieldName = nil;
    NSArray *headerLines = [headersString componentsSeparatedByString:@"\r\n"];
    for (NSString *line in headerLines) {
      if ([line hasPrefix:@"Content-Disposition:"]) {
        NSRange nameRange = [line rangeOfString:@"name=\""];
        if (nameRange.location != NSNotFound) {
          NSString *namePart = [line substringFromIndex:nameRange.location + 6];
          NSRange endQuote = [namePart rangeOfString:@"\""];
          if (endQuote.location != NSNotFound) {
            fieldName = [namePart substringToIndex:endQuote.location];
            break;
          }
        }
      }
    }

    if (!fieldName) {
      break;
    }

    // Extract body data
    position = separatorRange.location + separatorRange.length;
    NSRange nextBoundaryRange =
        [body rangeOfData:boundaryData
                  options:0
                    range:NSMakeRange(position, body.length - position)];

    NSUInteger bodyEnd;
    if (nextBoundaryRange.location != NSNotFound) {
      bodyEnd = nextBoundaryRange.location - 2; // -2 for CRLF before boundary
    } else {
      bodyEnd = body.length;
    }

    if (bodyEnd > position) {
      NSUInteger bodyLength = bodyEnd - position;
      NSData *fieldData =
          [body subdataWithRange:NSMakeRange(position, bodyLength)];

      // Remove trailing CRLF if present
      if (bodyLength >= 2) {
        NSData *trailingCrlf =
            [fieldData subdataWithRange:NSMakeRange(bodyLength - 2, 2)];
        if ([trailingCrlf
                isEqualToData:[@"\r\n"
                                  dataUsingEncoding:NSUTF8StringEncoding]]) {
          fieldData =
              [fieldData subdataWithRange:NSMakeRange(0, bodyLength - 2)];
        }
      }

      // Store based on field type
      if ([fieldName isEqualToString:@"blob"]) {
        // Binary field - keep as data
        formData[fieldName] = fieldData;
      } else {
        // Text field - convert to string
        NSString *textValue =
            [[NSString alloc] initWithData:fieldData
                                  encoding:NSUTF8StringEncoding];
        if (textValue) {
          formData[fieldName] =
              [textValue stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
      }
    }

    // Move position past this part
    if (nextBoundaryRange.location != NSNotFound) {
      position = nextBoundaryRange.location;
    } else {
      break;
    }
  }

  return formData.count > 0 ? [formData copy] : nil;
}

- (instancetype)parseFromData:(NSData *)data
                remoteAddress:(NSString *)remoteAddress {
  if (!data || data.length == 0) {
    return nil;
  }

  NSString *requestString =
      [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!requestString) {
    requestString =
        [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
  }

  if (!requestString) {
    return nil;
  }

  NSArray<NSString *> *lines =
      [requestString componentsSeparatedByString:@"\r\n"];
  if (lines.count == 0) {
    return nil;
  }

  NSString *requestLine = lines[0];
  NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
  if (parts.count < 2) {
    return nil;
  }

  NSString *methodString = parts[0];
  NSString *fullPath = parts[1];
  NSString *version = parts.count > 2 ? parts[2] : @"HTTP/1.1";

  NSString *path = fullPath;
  NSString *queryString = @"";

  NSRange queryRange = [fullPath rangeOfString:@"?"];
  if (queryRange.location != NSNotFound) {
    path = [fullPath substringToIndex:queryRange.location];
    queryString = [fullPath substringFromIndex:queryRange.location + 1];
  }

  NSDictionary<NSString *, NSString *> *queryParams =
      [self parseQueryParams:queryString];

  NSDictionary<NSString *, NSString *> *headers = [self parseHeaders:lines];

  NSData *body = [self parseBody:lines fromData:data];

  HttpMethod method = [self methodFromString:methodString];

  return [self initWithMethod:method
                 methodString:methodString
                         path:path
                  queryString:queryString
                  queryParams:queryParams
                      version:version
                      headers:headers
                         body:body
                remoteAddress:remoteAddress];
}

- (HttpMethod)methodFromString:(NSString *)methodString {
  if ([methodString isEqualToString:@"GET"])
    return HttpMethodGET;
  if ([methodString isEqualToString:@"POST"])
    return HttpMethodPOST;
  if ([methodString isEqualToString:@"PUT"])
    return HttpMethodPUT;
  if ([methodString isEqualToString:@"DELETE"])
    return HttpMethodDELETE;
  if ([methodString isEqualToString:@"PATCH"])
    return HttpMethodPATCH;
  if ([methodString isEqualToString:@"OPTIONS"])
    return HttpMethodOPTIONS;
  if ([methodString isEqualToString:@"HEAD"])
    return HttpMethodHEAD;
  return HttpMethodUnknown;
}

- (NSDictionary<NSString *, NSString *> *)parseHeaders:
    (NSArray<NSString *> *)lines {
  NSMutableDictionary<NSString *, NSString *> *headers =
      [NSMutableDictionary dictionary];

  for (NSUInteger i = 1; i < lines.count; i++) {
    NSString *line = lines[i];
    if (line.length == 0) {
      break;
    }

    NSRange colonRange = [line rangeOfString:@":"];
    if (colonRange.location != NSNotFound) {
      NSString *key = [[line substringToIndex:colonRange.location]
          stringByTrimmingCharactersInSet:[NSCharacterSet
                                              whitespaceCharacterSet]];
      NSString *value = [[line substringFromIndex:colonRange.location + 1]
          stringByTrimmingCharactersInSet:[NSCharacterSet
                                              whitespaceCharacterSet]];
      headers[key.lowercaseString] = value;
    }
  }

  return [headers copy];
}

- (NSData *)parseBody:(NSArray<NSString *> *)lines fromData:(NSData *)data {
  if (!data || data.length == 0) {
    return [NSData data];
  }

  NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSRange separatorRange =
      [data rangeOfData:separator options:0 range:NSMakeRange(0, data.length)];
  if (separatorRange.location == NSNotFound) {
    // Try fallback with \n\n if \r\n\r\n is missing
    separator = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    separatorRange = [data rangeOfData:separator
                               options:0
                                 range:NSMakeRange(0, data.length)];
    if (separatorRange.location == NSNotFound) {
      return [NSData data];
    }
  }

  NSUInteger bodyStart = separatorRange.location + separatorRange.length;
  if (bodyStart >= data.length) {
    return [NSData data];
  }

  return
      [data subdataWithRange:NSMakeRange(bodyStart, data.length - bodyStart)];
}

- (NSDictionary<NSString *, NSString *> *)parseQueryParams:
    (NSString *)queryString {
  if (queryString.length == 0) {
    return @{};
  }

  NSMutableDictionary<NSString *, NSString *> *params =
      [NSMutableDictionary dictionary];
  NSArray<NSString *> *pairs = [queryString componentsSeparatedByString:@"&"];

  for (NSString *pair in pairs) {
    NSRange eqRange = [pair rangeOfString:@"="];
    if (eqRange.location != NSNotFound) {
      NSString *key = [self urlDecode:[pair substringToIndex:eqRange.location]];
      NSString *value =
          [self urlDecode:[pair substringFromIndex:eqRange.location + 1]];
      params[key] = value;
    } else {
      params[[self urlDecode:pair]] = @"";
    }
  }

  return [params copy];
}

- (NSString *)urlDecode:(NSString *)string {
  NSString *result =
      [string stringByReplacingOccurrencesOfString:@"+" withString:@" "];
  result = [result stringByRemovingPercentEncoding];
  return result ?: string;
}

- (NSString *)headerForKey:(NSString *)key {
  return self.headers[key.lowercaseString];
}

- (NSString *)queryParamForKey:(NSString *)key {
  return self.queryParams[key];
}

@end

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/Space/PDSSpaceURI.h"

#import "Core/ATProtoValidator.h"
#import "Security/GZInputValidator.h"

NSString *const PDSSpaceURIErrorDomain = @"com.garazyk.space.uri";

/*
 * The upstream syntax grammar deliberately leaves `skey` application-defined:
 * it is a single AT-URI path segment, not necessarily a public-repo rkey.
 * Keep it opaque here so a space host does not reject an interoperable URI
 * before its type-specific policy has a chance to inspect it.
 */
static BOOL PDSSpaceURIIsValidSkey(NSString *value) {
  if (value.length == 0) {
    return NO;
  }
  NSCharacterSet *forbidden = [NSCharacterSet
      characterSetWithCharactersInString:@"/?#\\\\ \t\r\n"];
  if ([value rangeOfCharacterFromSet:forbidden].location != NSNotFound) {
    return NO;
  }
  for (NSUInteger index = 0; index < value.length; index++) {
    unichar character = [value characterAtIndex:index];
    if (character < 0x21 || character > 0x7e) {
      return NO;
    }
  }
  return YES;
}

@interface PDSSpaceURI ()
@property(nonatomic, readwrite, copy) NSString *authorityDID;
@property(nonatomic, readwrite, copy) NSString *spaceType;
@property(nonatomic, readwrite, copy) NSString *skey;
@property(nonatomic, readwrite, copy, nullable) NSString *authorDID;
@property(nonatomic, readwrite, copy, nullable) NSString *collection;
@property(nonatomic, readwrite, copy, nullable) NSString *rkey;
@property(nonatomic, readwrite, copy) NSString *spaceURI;
@property(nonatomic, readwrite, copy) NSString *URIString;
@property(nonatomic, readwrite, getter=isRecordURI) BOOL recordURI;
@end

@implementation PDSSpaceURI

+ (instancetype)URIWithString:(NSString *)URIString error:(NSError **)error {
  if (![URIString isKindOfClass:[NSString class]] ||
      ![URIString hasPrefix:@"at://"] ||
      URIString.length > 8192 ||
      [URIString rangeOfString:@"?"].location != NSNotFound ||
      [URIString rangeOfString:@"#"].location != NSNotFound) {
    return [self invalidFormat:@"A space URI must be an unqualified at:// URI"
                         error:error];
  }

  NSString *withoutScheme = [URIString substringFromIndex:5];
  NSArray<NSString *> *components = [withoutScheme componentsSeparatedByString:@"/"];
  if (components.count != 4 && components.count != 7) {
    return [self invalidFormat:@"A space URI must identify a space or a complete record"
                         error:error];
  }
  for (NSString *component in components) {
    if (component.length == 0) {
      return [self invalidFormat:@"Space URI components must be non-empty"
                           error:error];
    }
  }

  NSString *authority = components[0];
  NSString *marker = components[1];
  NSString *type = components[2];
  NSString *skey = components[3];
  if (![marker isEqualToString:@"space"]) {
    return [self invalidFormat:@"Permissioned URIs require the literal space marker"
                         error:error];
  }
  if (![ATProtoValidator validateDID:authority error:nil] ||
      ![ATProtoValidator validateNSID:type error:nil] ||
      !PDSSpaceURIIsValidSkey(skey)) {
    return [self invalidIdentifier:@"The space DID, type, or key is invalid" error:error];
  }

  NSString *author = nil;
  NSString *collection = nil;
  NSString *rkey = nil;
  if (components.count == 7) {
    author = components[4];
    collection = components[5];
    rkey = components[6];
    if (![ATProtoValidator validateDID:author error:nil] ||
        ![ATProtoValidator validateNSID:collection error:nil] ||
        ![[GZInputValidator sharedValidator] isValidRecordKey:rkey]) {
      return [self invalidIdentifier:@"The record author, collection, or key is invalid"
                                error:error];
    }
  }

  PDSSpaceURI *result = [[self alloc] init];
  result.authorityDID = authority;
  result.spaceType = type;
  result.skey = skey;
  result.authorDID = author;
  result.collection = collection;
  result.rkey = rkey;
  result.recordURI = (components.count == 7);
  result.spaceURI = [NSString stringWithFormat:@"at://%@/space/%@/%@", authority, type, skey];
  result.URIString = result.recordURI
      ? [NSString stringWithFormat:@"%@/%@/%@/%@", result.spaceURI, author, collection, rkey]
      : result.spaceURI;
  return result;
}

+ (instancetype)invalidFormat:(NSString *)message error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:PDSSpaceURIErrorDomain
                                 code:PDSSpaceURIErrorInvalidFormat
                             userInfo:@{NSLocalizedDescriptionKey : message}];
  }
  return nil;
}

+ (instancetype)invalidIdentifier:(NSString *)message error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:PDSSpaceURIErrorDomain
                                 code:PDSSpaceURIErrorInvalidIdentifier
                             userInfo:@{NSLocalizedDescriptionKey : message}];
  }
  return nil;
}

@end

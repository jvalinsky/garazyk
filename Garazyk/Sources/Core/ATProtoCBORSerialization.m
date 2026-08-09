// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ATProtoCBORSerialization.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/CBOR.h"

static NSData *CBORBase64URLDecode(NSString *string) {
    if (!string || ![string isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSMutableString *base64 = [string mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    while (base64.length % 4 != 0) {
        [base64 appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

/*!
 @abstract §S19 candidate 4 — the `_isContentAddressed` ivar is the routing
 flag that decides between the strict DAG-CBOR path (ATProtoDagCBOR) and the
 legacy / CTAP2 / generic-CBOR path (ATProtoCBORDecoder / ATProtoCBOREncoder). Set at
 construction; immutable for the lifetime of the instance.
 */
@interface ATProtoCBORSerialization ()
@end

@implementation ATProtoCBORSerialization

- (nullable instancetype)initWithContentAddressed:(BOOL)contentAddressed {
  self = [super init];
  if (self) {
    _isContentAddressed = contentAddressed;
  }
  return self;
}

- (NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error {
  ATProtoCBORValue *cbor = [ATProtoCBORSerialization cborValueFromObject:obj];
  if (!cbor) {
    if (error)
      *error = [NSError errorWithDomain:@"ATProtoCBORSerialization"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to convert object to CBOR"
                               }];
    return nil;
  }
  return [ATProtoCBOREncoder encode:cbor];
}

- (id)JSONObjectWithData:(NSData *)data error:(NSError **)error {
  // §S19 candidate 4: branch the wrapped [ATProtoCBORDecoder decode:] call on
  // _isContentAddressed. Content-addressed callers (ATProtoRepoCommit, ATProtoMST/CAR
  // blocks, Firehose, AppView ingest, sync, identity, profile records)
  // route through the strict [ATProtoDagCBOR decodeDataAsJSON:] path --
  // the same dispatch as the direct-from-DagCBOR identity at
  // AppViewBackfillWorker.m:422. CTAP2 / generic-CBOR callers (lexicon
  // schemas and similar non-ATProtoCID'd payloads) stay on the legacy
  // [ATProtoCBORDecoder decode:] path.
  if (self.isContentAddressed) {
    return [ATProtoDagCBOR decodeDataAsJSON:data error:error];
  }
  // Fallthrough: generic / CTAP2 callers stay on the legacy decoder.
  ATProtoCBORValue *cbor = [ATProtoCBORDecoder decode:data];
  if (!cbor) {
    if (error)
      *error = [NSError
          errorWithDomain:@"ATProtoCBORSerialization"
                     code:2
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to decode CBOR data"
                 }];
    return nil;
  }
  return [ATProtoCBORSerialization objectFromCBORValue:cbor];
}

#pragma mark - Private Helpers

+ (ATProtoCBORValue *)cborValueFromObject:(id)obj {
  if ([obj isKindOfClass:[NSDictionary class]]) {
    NSDictionary *json = (NSDictionary *)obj;

    // ATProto lex-to-IPLD: convert {"$link": "bafyrei..."} to CBOR Tag 42 (ATProtoCID)
    if (json.count == 1 && [json[@"$link"] isKindOfClass:[NSString class]]) {
      NSString *cidStr = json[@"$link"];
      ATProtoCID *cid = [ATProtoCID cidFromString:cidStr];
      if (cid) {
        NSData *cidBytes = [cid bytes];
        // DAG-CBOR Tag 42 requires 0x00 identity multibase prefix before ATProtoCID
        // bytes
        NSMutableData *tagPayload =
            [NSMutableData dataWithCapacity:1 + cidBytes.length];
        uint8_t identityPrefix = 0x00;
        [tagPayload appendBytes:&identityPrefix length:1];
        [tagPayload appendData:cidBytes];
        return [ATProtoCBORValue tag:42 value:[ATProtoCBORValue byteString:tagPayload]];
      }
    }

    // ATProto lex-to-IPLD: convert {"$bytes": "base64..."} to CBOR byte string
    if (json.count == 1 && [json[@"$bytes"] isKindOfClass:[NSString class]]) {
      NSString *b64 = json[@"$bytes"];
      NSData *bytes = CBORBase64URLDecode(b64);
      return [ATProtoCBORValue byteString:bytes ?: [NSData data]];
    }

    NSArray *sortedKeys = [[json allKeys]
        sortedArrayUsingComparator:^NSComparisonResult(id _Nonnull obj1,
                                                        id _Nonnull obj2) {
          NSString *s1 = (NSString *)obj1;
          NSString *s2 = (NSString *)obj2;
          return [s1 compare:s2 options:NSLiteralSearch];
        }];

    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (id key in sortedKeys) {
      ATProtoCBORValue *keyVal = [self cborValueFromObject:key];
      ATProtoCBORValue *valVal = [ATProtoCBORSerialization cborValueFromObject:[obj objectForKey:key]];
      if (keyVal && valVal) {
        map[keyVal] = valVal;
      }
    }
    return [ATProtoCBORValue map:map];
  } else if ([obj isKindOfClass:[NSArray class]]) {
    NSMutableArray *arr = [NSMutableArray array];
    for (id item in obj) {
      ATProtoCBORValue *val = [ATProtoCBORSerialization cborValueFromObject:item];
      if (val)
        [arr addObject:val];
    }
    return [ATProtoCBORValue array:arr];
  } else if ([obj isKindOfClass:[NSString class]]) {
    return [ATProtoCBORValue textString:obj];
  } else if ([obj isKindOfClass:[NSNumber class]]) {
    // Handle boolean using CFTypeID check
    // This avoids issues with @encode(BOOL) varying across platforms (signed
    // char vs bool)
    if (CFGetTypeID((__bridge CFTypeRef)obj) == CFBooleanGetTypeID()) {
      return [obj boolValue] ? [ATProtoCBORValue simple:21] : [ATProtoCBORValue simple:20];
    }

    // Handle integer vs float
    const char *objCType = [obj objCType];
    if (strcmp(objCType, @encode(float)) == 0 ||
        strcmp(objCType, @encode(double)) == 0) {
      // It's float
      // But ATProtoCBORValue only has simple/float?
      // Actually ATProtoCBORValue.m has decodeSimpleOrFloat but init methods are
      // limited. Wait, ATProtoCBORValue has +tag:value: but simplistic support. Let's
      // check ATProtoCBORValue class capabilities. It has initWithType... and
      // properties like unsignedInteger, negativeInteger. But does it support
      // float? encodeFloatValue implementation exists. But ATProtoCBORValue
      // structure... Let's assume NSNumber is integer for simplicity unless it
      // forces float. DAG-CBOR prefers integers. But if it has decimal... For
      // now, treat as integer if possible.
      double d = [obj doubleValue];
      long long l = [obj longLongValue];
      if (d == (double)l) {
        if (l >= 0)
          return [ATProtoCBORValue unsignedInteger:(NSUInteger)l];
        else
          return [ATProtoCBORValue negativeInteger:(NSInteger)l];
      }
      // Float support missing in ATProtoCBORValue object wrapper?
      // Let's check ATProtoCBORValue interface.
      return nil; // Not fully supported yet
    } else {
      long long l = [obj longLongValue];
      if (l >= 0)
        return [ATProtoCBORValue unsignedInteger:(NSUInteger)l];
      else
        return [ATProtoCBORValue negativeInteger:(NSInteger)l];
    }
  } else if ([obj isKindOfClass:[NSNull class]]) {
    return [ATProtoCBORValue simple:22];
  } else if ([obj isKindOfClass:[NSData class]]) {
    return [ATProtoCBORValue byteString:obj];
  }
  return nil;
}

+ (id)objectFromCBORValue:(ATProtoCBORValue *)cbor {
  switch (cbor.type) {
  case CBORTypeUnsignedInteger:
    return @(cbor.unsignedInteger.unsignedIntegerValue);
  case CBORTypeNegativeInteger:
    return @(cbor.negativeInteger.integerValue);
  case CBORTypeByteString: {
    // ATProto IPLD-to-lex: convert CBOR byte string to {"$bytes": "base64..."}
    NSString *b64 = [cbor.byteString base64EncodedStringWithOptions:0];
    return @{@"$bytes" : b64 ?: @""};
  }
  case CBORTypeTextString:
    return cbor.textString;
  case CBORTypeArray: {
    NSMutableArray *arr = [NSMutableArray array];
    for (ATProtoCBORValue *val in cbor.array) {
      id obj = [ATProtoCBORSerialization objectFromCBORValue:val];
      if (obj)
        [arr addObject:val];
    }
    return arr;
  }
  case CBORTypeMap: {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (ATProtoCBORValue *key in cbor.map) {
      id keyObj = [ATProtoCBORSerialization objectFromCBORValue:key];
      id valObj = [ATProtoCBORSerialization objectFromCBORValue:cbor.map[key]];
      if (keyObj && valObj) {
        // JSON keys must be strings
        if ([keyObj isKindOfClass:[NSString class]]) {
          dict[keyObj] = valObj;
        }
      }
    }
    return dict;
  }
  case CBORTypeTag: {
    // ATProto IPLD-to-lex: convert CBOR Tag 42 (ATProtoCID) to {"$link": "bafyrei..."}
    if (cbor.tag.unsignedIntegerValue == 42 &&
        cbor.tagValue.type == CBORTypeByteString) {
      NSData *tagPayload = cbor.tagValue.byteString;
      // Strip 0x00 identity multibase prefix
      if (tagPayload.length > 1) {
        const uint8_t *payloadBytes = tagPayload.bytes;
        if (payloadBytes[0] == 0x00) {
          NSData *cidBytes = [tagPayload
              subdataWithRange:NSMakeRange(1, tagPayload.length - 1)];
          ATProtoCID *cid = [ATProtoCID cidFromBytes:cidBytes];
          if (cid) {
            return @{@"$link" : [cid stringValue]};
          }
        }
      }
    }
    // For other tags, decode the inner value
    return [ATProtoCBORSerialization objectFromCBORValue:cbor.tagValue];
  }
  case CBORTypeSimpleOrFloat:
    if (cbor.simpleValue.unsignedIntegerValue == 20)
      return @NO;
    if (cbor.simpleValue.unsignedIntegerValue == 21)
      return @YES;
    if (cbor.simpleValue.unsignedIntegerValue == 22)
      return [NSNull null];
    return nil;
  default:
    return nil;
  }
}

@end

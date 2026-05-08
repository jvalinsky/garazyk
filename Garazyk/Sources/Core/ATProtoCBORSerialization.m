#import "ATProtoCBORSerialization.h"
#import "Core/CID.h"
#import "Repository/CBOR.h"
#import <Security/Security.h>

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

@implementation ATProtoCBORSerialization

+ (NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error {
  CBORValue *cbor = [self cborValueFromObject:obj];
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
  return [CBOREncoder encode:cbor];
}

+ (id)JSONObjectWithData:(NSData *)data error:(NSError **)error {
  CBORValue *cbor = [CBORDecoder decode:data];
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
  return [self objectFromCBORValue:cbor];
}

#pragma mark - Private Helpers

+ (CBORValue *)cborValueFromObject:(id)obj {
  if ([obj isKindOfClass:[NSDictionary class]]) {
    NSDictionary *json = (NSDictionary *)obj;

    // ATProto lex-to-IPLD: convert {"$link": "bafyrei..."} to CBOR Tag 42 (CID)
    if (json.count == 1 && [json[@"$link"] isKindOfClass:[NSString class]]) {
      NSString *cidStr = json[@"$link"];
      CID *cid = [CID cidFromString:cidStr];
      if (cid) {
        NSData *cidBytes = [cid bytes];
        // DAG-CBOR Tag 42 requires 0x00 identity multibase prefix before CID
        // bytes
        NSMutableData *tagPayload =
            [NSMutableData dataWithCapacity:1 + cidBytes.length];
        uint8_t identityPrefix = 0x00;
        [tagPayload appendBytes:&identityPrefix length:1];
        [tagPayload appendData:cidBytes];
        return [CBORValue tag:42 value:[CBORValue byteString:tagPayload]];
      }
    }

    // ATProto lex-to-IPLD: convert {"$bytes": "base64..."} to CBOR byte string
    if (json.count == 1 && [json[@"$bytes"] isKindOfClass:[NSString class]]) {
      NSString *b64 = json[@"$bytes"];
      NSData *bytes = CBORBase64URLDecode(b64);
      return [CBORValue byteString:bytes ?: [NSData data]];
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
      CBORValue *keyVal = [self cborValueFromObject:key];
      CBORValue *valVal = [self cborValueFromObject:[obj objectForKey:key]];
      if (keyVal && valVal) {
        map[keyVal] = valVal;
      }
    }
    return [CBORValue map:map];
  } else if ([obj isKindOfClass:[NSArray class]]) {
    NSMutableArray *arr = [NSMutableArray array];
    for (id item in obj) {
      CBORValue *val = [self cborValueFromObject:item];
      if (val)
        [arr addObject:val];
    }
    return [CBORValue array:arr];
  } else if ([obj isKindOfClass:[NSString class]]) {
    return [CBORValue textString:obj];
  } else if ([obj isKindOfClass:[NSNumber class]]) {
    // Handle boolean using CFTypeID check
    // This avoids issues with @encode(BOOL) varying across platforms (signed
    // char vs bool)
    if (CFGetTypeID((__bridge CFTypeRef)obj) == CFBooleanGetTypeID()) {
      return [obj boolValue] ? [CBORValue simple:21] : [CBORValue simple:20];
    }

    // Handle integer vs float
    const char *objCType = [obj objCType];
    if (strcmp(objCType, @encode(float)) == 0 ||
        strcmp(objCType, @encode(double)) == 0) {
      // It's float
      // But CBORValue only has simple/float?
      // Actually CBORValue.m has decodeSimpleOrFloat but init methods are
      // limited. Wait, CBORValue has +tag:value: but simplistic support. Let's
      // check CBORValue class capabilities. It has initWithType... and
      // properties like unsignedInteger, negativeInteger. But does it support
      // float? encodeFloatValue implementation exists. But CBORValue
      // structure... Let's assume NSNumber is integer for simplicity unless it
      // forces float. DAG-CBOR prefers integers. But if it has decimal... For
      // now, treat as integer if possible.
      double d = [obj doubleValue];
      long long l = [obj longLongValue];
      if (d == (double)l) {
        if (l >= 0)
          return [CBORValue unsignedInteger:(NSUInteger)l];
        else
          return [CBORValue negativeInteger:(NSInteger)l];
      }
      // Float support missing in CBORValue object wrapper?
      // Let's check CBORValue interface.
      return nil; // Not fully supported yet
    } else {
      long long l = [obj longLongValue];
      if (l >= 0)
        return [CBORValue unsignedInteger:(NSUInteger)l];
      else
        return [CBORValue negativeInteger:(NSInteger)l];
    }
  } else if ([obj isKindOfClass:[NSNull class]]) {
    return [CBORValue simple:22];
  } else if ([obj isKindOfClass:[NSData class]]) {
    return [CBORValue byteString:obj];
  }
  return nil;
}

+ (id)objectFromCBORValue:(CBORValue *)cbor {
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
    for (CBORValue *val in cbor.array) {
      id obj = [self objectFromCBORValue:val];
      if (obj)
        [arr addObject:obj];
    }
    return arr;
  }
  case CBORTypeMap: {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (CBORValue *key in cbor.map) {
      id keyObj = [self objectFromCBORValue:key];
      id valObj = [self objectFromCBORValue:cbor.map[key]];
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
    // ATProto IPLD-to-lex: convert CBOR Tag 42 (CID) to {"$link": "bafyrei..."}
    if (cbor.tag.unsignedIntegerValue == 42 &&
        cbor.tagValue.type == CBORTypeByteString) {
      NSData *tagPayload = cbor.tagValue.byteString;
      // Strip 0x00 identity multibase prefix
      if (tagPayload.length > 1) {
        const uint8_t *payloadBytes = tagPayload.bytes;
        if (payloadBytes[0] == 0x00) {
          NSData *cidBytes = [tagPayload
              subdataWithRange:NSMakeRange(1, tagPayload.length - 1)];
          CID *cid = [CID cidFromBytes:cidBytes];
          if (cid) {
            return @{@"$link" : [cid stringValue]};
          }
        }
      }
    }
    // For other tags, decode the inner value
    return [self objectFromCBORValue:cbor.tagValue];
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

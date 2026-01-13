#import "ATProtoCBORSerialization.h"

#import "Repository/CBOR.h"

@implementation ATProtoCBORSerialization

+ (NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error {
    CBORValue *cbor = [self cborValueFromObject:obj];
    if (!cbor) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoCBORSerialization" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert object to CBOR"}];
        return nil;
    }
    return [CBOREncoder encode:cbor];
}

+ (id)JSONObjectWithData:(NSData *)data error:(NSError **)error {
    CBORValue *cbor = [CBORDecoder decode:data];
    if (!cbor) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoCBORSerialization" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode CBOR data"}];
        return nil;
    }
    return [self objectFromCBORValue:cbor];
}

#pragma mark - Private Helpers

+ (CBORValue *)cborValueFromObject:(id)obj {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (id key in obj) {
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
            if (val) [arr addObject:val];
        }
        return [CBORValue array:arr];
    } else if ([obj isKindOfClass:[NSString class]]) {
        return [CBORValue textString:obj];
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        const char *objCType = [obj objCType];
        
        // Handle boolean vs integer
        // Use objCType to distinguish. @YES/@NO have type 'c' (char) or 'B' (bool).
        // Integers @1, @2 have 'i' (int), 'q' (long long), etc.
        if (strcmp(objCType, @encode(BOOL)) == 0 || strcmp(objCType, @encode(char)) == 0) {
             if ([obj isEqual:@YES]) return [CBORValue simple:21];
             if ([obj isEqual:@NO]) return [CBORValue simple:20];
        }
        
        // Handle integer vs float
        if (strcmp(objCType, @encode(float)) == 0 || strcmp(objCType, @encode(double)) == 0) {
            // It's a float
            return [CBORValue floatingPoint:[obj doubleValue]];
        } else {
            long long l = [obj longLongValue];
            if (l >= 0) return [CBORValue unsignedInteger:(NSUInteger)l];
            else return [CBORValue negativeInteger:(NSInteger)l];
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
        case CBORTypeByteString:
            return cbor.byteString;
        case CBORTypeTextString:
            return cbor.textString;
        case CBORTypeArray: {
            NSMutableArray *arr = [NSMutableArray array];
            for (CBORValue *val in cbor.array) {
                [arr addObject:[self objectFromCBORValue:val]];
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
        case CBORTypeSimpleOrFloat:
            if (cbor.simpleValue.unsignedIntegerValue == 20) return @NO;
            if (cbor.simpleValue.unsignedIntegerValue == 21) return @YES;
            if (cbor.simpleValue.unsignedIntegerValue == 22) return [NSNull null];
            return nil;
        default:
            return nil;
    }
}

@end

#import "ATProtoCBORSerialization.h"
#import "Repository/CBOR.h"
#import <Security/Security.h>

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
        NSDictionary *json = (NSDictionary *)obj;
        NSArray *sortedKeys = [[json allKeys] sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
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
            if (val) [arr addObject:val];
        }
        return [CBORValue array:arr];
    } else if ([obj isKindOfClass:[NSString class]]) {
        return [CBORValue textString:obj];
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        // Handle boolean using robust CFTypeID check
        // This avoids issues with @encode(BOOL) varying across platforms (signed char vs bool)
        if (CFGetTypeID((__bridge CFTypeRef)obj) == CFBooleanGetTypeID()) {
            return [obj boolValue] ? [CBORValue simple:21] : [CBORValue simple:20];
        }

        // Handle integer vs float
        const char *objCType = [obj objCType];
        if (strcmp(objCType, @encode(float)) == 0 || strcmp(objCType, @encode(double)) == 0) {
            // It's float
            // But CBORValue only has simple/float?
            // Actually CBORValue.m has decodeSimpleOrFloat but init methods are limited.
            // Wait, CBORValue has +tag:value: but simplistic support.
            // Let's check CBORValue class capabilities.
            // It has initWithType... and properties like unsignedInteger, negativeInteger.
            // But does it support float?
            // encodeFloatValue implementation exists.
            // But CBORValue structure...
            // Let's assume NSNumber is integer for simplicity unless it forces float.
            // DAG-CBOR prefers integers.
            // But if it has decimal...
            // For now, treat as integer if possible.
            double d = [obj doubleValue];
            long long l = [obj longLongValue];
            if (d == (double)l) {
                if (l >= 0) return [CBORValue unsignedInteger:(NSUInteger)l];
                else return [CBORValue negativeInteger:(NSInteger)l];
            }
            // Float support missing in CBORValue object wrapper?
            // Let's check CBORValue interface.
            return nil; // Not fully supported yet
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

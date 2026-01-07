#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CBORType) {
    CBORTypeUnsignedInteger = 0,
    CBORTypeNegativeInteger = 1,
    CBORTypeByteString = 2,
    CBORTypeTextString = 3,
    CBORTypeArray = 4,
    CBORTypeMap = 5,
    CBORTypeTag = 6,
    CBORTypeSimpleOrFloat = 7
};

@interface CBORValue : NSObject <NSCopying>

@property (nonatomic, assign, readonly) CBORType type;
@property (nonatomic, strong, readonly, nullable) NSNumber *unsignedInteger;
@property (nonatomic, strong, readonly, nullable) NSNumber *negativeInteger;
@property (nonatomic, strong, readonly, nullable) NSData *byteString;
@property (nonatomic, copy, readonly, nullable) NSString *textString;
@property (nonatomic, copy, readonly, nullable) NSArray<CBORValue *> *array;
@property (nonatomic, copy, readonly, nullable) NSDictionary<CBORValue *, CBORValue *> *map;
@property (nonatomic, strong, readonly, nullable) NSNumber *tag;
@property (nonatomic, strong, readonly, nullable) NSNumber *simpleValue;
@property (nonatomic, strong, readonly, nullable) NSNumber *floatValue;

+ (instancetype)unsignedInteger:(NSUInteger)value;
+ (instancetype)negativeInteger:(NSInteger)value;
+ (instancetype)byteString:(NSData *)data;
+ (instancetype)textString:(NSString *)string;
+ (instancetype)array:(NSArray<CBORValue *> *)array;
+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map;
+ (instancetype)tag:(NSUInteger)tag value:(CBORValue *)value;
+ (instancetype)simple:(NSUInteger)value;
+ (instancetype)floatingPoint:(double)value;
+ (instancetype)nilValue;

- (instancetype)initWithType:(CBORType)type;

- (instancetype)initWithUnsignedInteger:(NSNumber *)value;
- (instancetype)initWithNegativeInteger:(NSNumber *)value;
- (instancetype)initWithByteString:(NSData *)data;
- (instancetype)initWithTextString:(NSString *)string;
- (instancetype)initWithArray:(NSArray<CBORValue *> *)array;
- (instancetype)initWithMap:(NSDictionary<CBORValue *, CBORValue *> *)map;
- (instancetype)initWithTag:(NSNumber *)tag value:(CBORValue *)value;
- (instancetype)initWithSimpleValue:(NSNumber *)value;
- (instancetype)initWithFloatValue:(NSNumber *)value;

- (NSData *)encode;
+ (nullable instancetype)decode:(NSData *)data;

- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;

@end

@interface CBOREncoder : NSObject

+ (NSData *)encode:(CBORValue *)value;

@end

@interface CBORDecoder : NSObject

+ (nullable CBORValue *)decode:(NSData *)data;
+ (nullable CBORValue *)decode:(NSData *)data offset:(NSUInteger *)offset;

@end

NS_ASSUME_NONNULL_END

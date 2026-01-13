#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PLCOperationErrorDomain;

typedef NS_ENUM(NSInteger, PLCOperationError) {
    PLCOperationErrorInvalidType = 1,
    PLCOperationErrorMissingPrev = 2,
    PLCOperationErrorInvalidRotationKeys = 3,
    PLCOperationErrorInvalidAlsoKnownAs = 4,
    PLCOperationErrorInvalidServices = 5,
    PLCOperationErrorSerializationFailed = 6,
    PLCOperationErrorCIDComputationFailed = 7
};

@interface PLCOperation : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *type;
@property (nonatomic, strong) NSArray<NSString *> *rotationKeys;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *verificationMethods;
@property (nonatomic, strong) NSArray<NSString *> *alsoKnownAs;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *services;
@property (nonatomic, copy, nullable) NSString *prev;
@property (nonatomic, copy, nullable) NSString *sig;

+ (instancetype)genesisOperationWithRotationKeys:(NSArray<NSString *> *)rotationKeys
                               verificationMethods:(NSDictionary<NSString *, NSString *> *)verificationMethods
                                      alsoKnownAs:(NSArray<NSString *> *)alsoKnownAs
                                         services:(NSDictionary<NSString *, NSDictionary *> *)services;

+ (instancetype)tombstoneOperationWithPrev:(NSString *)prevCID
                             rotationKeys:(NSArray<NSString *> *)rotationKeys;

- (BOOL)isGenesis;
- (BOOL)isTombstone;

- (nullable NSData *)serializeForSigning:(NSError **)error;
- (nullable NSString *)computeCID:(NSError **)error;

+ (nullable instancetype)operationFromJSON:(NSDictionary *)json error:(NSError **)error;
- (NSDictionary *)toJSON;

@end

NS_ASSUME_NONNULL_END

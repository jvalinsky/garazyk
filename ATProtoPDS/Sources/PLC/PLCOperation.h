#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PLCOperation : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy, nullable) NSString *prev;
@property (nonatomic, copy) NSString *sig;
@property (nonatomic, copy) NSDictionary *data;

+ (NSString *)calculateDIDForData:(NSDictionary *)data;
+ (nullable instancetype)operationFromDictionary:(NSDictionary *)dict error:(NSError **)error;
- (NSDictionary *)toDictionary;

@end

@interface PLCDIDState : NSObject
@property (nonatomic, copy) NSString *did;
@property (nonatomic, strong) NSArray<NSString *> *rotationKeys;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *verificationMethods;
@property (nonatomic, strong) NSArray<NSString *> *alsoKnownAs;
@property (nonatomic, strong) NSDictionary *services;
@property (nonatomic, assign) BOOL tombstoned;

- (NSDictionary *)toDIDDocument;
@end

@interface PLCStateReplayer : NSObject
+ (nullable PLCDIDState *)replayHistory:(NSArray<PLCOperation *> *)history error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END

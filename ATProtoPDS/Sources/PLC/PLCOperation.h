#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PLCOperation : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy, nullable) NSString *prev;
@property (nonatomic, copy) NSString *sig;
@property (nonatomic, copy) NSDictionary *data;

+ (nullable instancetype)operationFromDictionary:(NSDictionary *)dict error:(NSError **)error;
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END

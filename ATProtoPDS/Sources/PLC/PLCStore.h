#import <Foundation/Foundation.h>
#import "PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PLCStore <NSObject>

- (nullable NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did error:(NSError **)error;
- (BOOL)appendOperation:(PLCOperation *)op error:(NSError **)error;
- (nullable NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

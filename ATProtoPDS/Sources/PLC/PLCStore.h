#import <Foundation/Foundation.h>
#import "PLCOperation.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PLCStore <NSObject>

- (nullable NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did
                                      includeNullified:(BOOL)includeNullified
                                                 error:(NSError **)error;
- (BOOL)appendOperation:(PLCOperation *)op
           nullifyCIDs:(NSArray<NSString *> *)nullified
                 error:(NSError **)error;
- (nullable NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error;

- (nullable PLCOperation *)getLatestOperationForDID:(NSString *)did error:(NSError **)error;

- (nullable NSArray<PLCOperation *> *)exportOperationsAfter:(nullable NSDate *)after
                                                      count:(NSUInteger)count
                                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

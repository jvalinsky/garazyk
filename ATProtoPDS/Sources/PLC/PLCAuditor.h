#import <Foundation/Foundation.h>
#import "PLCStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface PLCAuditor : NSObject

- (instancetype)initWithStore:(id<PLCStore>)store;
- (BOOL)verifyDID:(NSString *)did error:(NSError **)error;
- (BOOL)verifyOperation:(PLCOperation *)op
	           proposedDate:(NSDate *)proposedDate
	          nullifiedCIDs:(NSArray<NSString *> * _Nullable __autoreleasing * _Nullable)nullified
	                  error:(NSError **)error;
- (BOOL)verifyOperation:(PLCOperation *)op error:(NSError **)error;
- (NSData *)hashForOperationData:(NSDictionary *)data;

@end

NS_ASSUME_NONNULL_END

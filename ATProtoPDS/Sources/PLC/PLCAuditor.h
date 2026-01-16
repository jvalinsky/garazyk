#import <Foundation/Foundation.h>
#import "PLCStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface PLCAuditor : NSObject

- (instancetype)initWithStore:(id<PLCStore>)store;
- (BOOL)verifyDID:(NSString *)did error:(NSError **)error;
- (NSData *)hashForOperationData:(NSDictionary *)data;

@end

NS_ASSUME_NONNULL_END

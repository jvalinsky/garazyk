#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSRepoRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@interface PDSSQLiteRepoRepository : NSObject <PDSRepoRepository>

- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool;

@end

NS_ASSUME_NONNULL_END

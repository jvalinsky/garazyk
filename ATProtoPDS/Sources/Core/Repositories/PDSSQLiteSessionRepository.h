#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSSessionRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@interface PDSSQLiteSessionRepository : NSObject <PDSSessionRepository>

- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool;

@end

NS_ASSUME_NONNULL_END

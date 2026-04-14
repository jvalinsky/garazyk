#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSBlockRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@interface PDSSQLiteBlockRepository : NSObject <PDSBlockRepository>

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

@end

NS_ASSUME_NONNULL_END

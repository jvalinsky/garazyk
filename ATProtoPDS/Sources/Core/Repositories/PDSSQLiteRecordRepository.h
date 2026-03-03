#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSRecordRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@interface PDSSQLiteRecordRepository : NSObject <PDSRecordRepository>

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

@end

NS_ASSUME_NONNULL_END

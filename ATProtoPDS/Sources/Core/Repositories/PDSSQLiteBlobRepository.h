#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSBlobRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@interface PDSSQLiteBlobRepository : NSObject <PDSBlobRepository>

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

@end

NS_ASSUME_NONNULL_END

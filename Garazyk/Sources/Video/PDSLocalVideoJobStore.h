#import <Foundation/Foundation.h>
#import "Video/VideoJobStore.h"

@class PDSDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface PDSLocalVideoJobStore : NSObject <VideoJobStore>

@property (nonatomic, strong, readonly) PDSDatabase *database;

- (instancetype)initWithDatabase:(PDSDatabase *)database;

@end

NS_ASSUME_NONNULL_END

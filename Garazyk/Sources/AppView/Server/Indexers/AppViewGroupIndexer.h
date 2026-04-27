#import "AppViewIndexer.h"

@class AppViewDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface AppViewGroupIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database;

@end

NS_ASSUME_NONNULL_END
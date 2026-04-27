#import "AppViewIndexer.h"

@class AppViewDatabase;
@class BookmarkService;

NS_ASSUME_NONNULL_BEGIN

@class BookmarkService;

@interface AppViewBookmarkIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database
               bookmarkService:(BookmarkService *)bookmarkService;

@end

NS_ASSUME_NONNULL_END
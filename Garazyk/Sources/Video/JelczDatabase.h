#import <Foundation/Foundation.h>
#import "Video/VideoJobStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface JelczDatabase : NSObject <VideoJobStore>

- (nullable instancetype)initWithDatabasePath:(NSString *)path
                                       error:(NSError **)error;

- (BOOL)openDatabaseWithError:(NSError **)error;
- (void)closeDatabase;

- (NSArray<NSDictionary *> *)listVideoJobsWithState:(nullable NSString *)state
                                               limit:(NSUInteger)limit
                                              offset:(NSUInteger)offset
                                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

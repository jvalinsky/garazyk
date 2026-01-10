#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@interface PDSRepositoryService : NSObject

@property (nonatomic, weak) PDSDatabasePool *databasePool;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Repo Operations

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error;

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

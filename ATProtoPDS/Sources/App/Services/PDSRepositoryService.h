#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@class MST;
@class CID;

@interface PDSRepositoryService : NSObject

@property (nonatomic, weak) PDSDatabasePool *databasePool;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Repo Operations

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error;

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error;

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

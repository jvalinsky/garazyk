#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSActorStore;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlock;
@protocol PDSActorStoreReader;
@protocol PDSActorStoreTransactor;

extern NSString * const PDSDatabasePoolErrorDomain;

typedef NS_ENUM(NSInteger, PDSDatabasePoolError) {
    PDSDatabasePoolErrorStoreNotFound = 1000,
    PDSDatabasePoolErrorStoreClosed,
    PDSDatabasePoolErrorTransactionFailed,
};

@interface PDSDatabasePool : NSObject

@property (nonatomic, copy, readonly) NSString *dbDirectory;
@property (nonatomic, assign, readonly) NSUInteger maxSize;
@property (nonatomic, assign, readonly) NSUInteger currentSize;
@property (nonatomic, assign, readonly) NSUInteger openFileHandleCount;

- (instancetype)initWithDbDirectory:(NSString *)dbDirectory maxSize:(NSUInteger)maxSize;

- (nullable PDSActorStore *)storeForDid:(NSString *)did error:(NSError **)error;

- (void)transactWithDid:(NSString *)did 
                  block:(void (^)(id<PDSActorStoreTransactor> transactor))block 
                  error:(NSError **)error;

- (void)readWithDid:(NSString *)did 
               block:(void (^)(id<PDSActorStoreReader> reader))block 
               error:(NSError **)error;

- (nullable PDSDatabaseAccount *)getAccount:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseRepo *)getRepo:(NSString *)did error:(NSError **)error;
- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;

- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;
- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error;

- (void)evictUnusedStores;
- (void)evictStoreForDid:(NSString *)did;
- (void)closeAll;

- (NSDictionary<NSString *, id> *)collectMetrics;

@end

NS_ASSUME_NONNULL_END

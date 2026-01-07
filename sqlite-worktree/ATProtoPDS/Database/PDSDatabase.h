#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSDatabaseErrorDomain;

typedef NS_ENUM(NSInteger, PDSDatabaseError) {
    PDSDatabaseErrorNotOpen = 1000,
    PDSDatabaseErrorQueryFailed = 1001,
    PDSDatabaseErrorMigrationFailed = 1002,
    PDSDatabaseErrorConstraintViolation = 1003,
    PDSDatabaseErrorNotFound = 1004,
};

@interface PDSDatabase : NSObject

@property (nonatomic, readonly) NSURL *databaseURL;
@property (nonatomic, readonly) BOOL isOpen;

+ (instancetype)databaseAtURL:(NSURL *)url;

- (BOOL)openWithError:(NSError **)error;
- (void)close;

- (BOOL)executeRawSQL:(NSString *)sql error:(NSError **)error;
- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql error:(NSError **)error;

@end

@interface PDSDatabaseAccount : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy, nullable) NSString *email;
@property (nonatomic, copy, nullable) NSData *passwordHash;
@property (nonatomic, copy, nullable) NSData *accessJwt;
@property (nonatomic, copy, nullable) NSData *refreshJwt;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;

@end

@interface PDSDatabaseRepo : NSObject

@property (nonatomic, copy) NSString *ownerDid;
@property (nonatomic, copy) NSData *rootCid;
@property (nonatomic, copy, nullable) NSData *collectionData;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;

@end

@interface PDSDatabaseBlock : NSObject

@property (nonatomic, copy) NSData *cid;
@property (nonatomic, copy) NSString *repoDid;
@property (nonatomic, copy, nullable) NSData *blockData;
@property (nonatomic, copy, nullable) NSString *contentType;
@property (nonatomic, assign) NSInteger size;
@property (nonatomic, strong) NSDate *createdAt;

@end

@interface PDSDatabase (Accounts)

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error;
- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error;
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

@end

@interface PDSDatabase (Repos)

- (BOOL)createRepo:(PDSDatabaseRepo *)repo error:(NSError **)error;
- (BOOL)updateRepoRoot:(NSString *)ownerDid rootCid:(NSData *)rootCid error:(NSError **)error;
- (nullable PDSDatabaseRepo *)getRepoForDid:(NSString *)did error:(NSError **)error;
- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error;
- (BOOL)deleteRepo:(NSString *)ownerDid error:(NSError **)error;

@end

@interface PDSDatabase (Blocks)

- (BOOL)saveBlock:(PDSDatabaseBlock *)block error:(NSError **)error;
- (BOOL)saveBlocks:(NSArray<PDSDatabaseBlock *> *)blocks error:(NSError **)error;
- (nullable PDSDatabaseBlock *)getBlockWithCid:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;
- (NSArray<PDSDatabaseBlock *> *)getBlocksForRepo:(NSString *)repoDid limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error;
- (NSInteger)getBlockCountForRepo:(NSString *)repoDid error:(NSError **)error;
- (BOOL)deleteBlock:(NSData *)cid repoDid:(NSString *)repoDid error:(NSError **)error;

@end

@interface PDSDatabase (Transactions)

- (BOOL)beginTransactionWithError:(NSError **)error;
- (BOOL)commitTransactionWithError:(NSError **)error;
- (BOOL)rollbackTransactionWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

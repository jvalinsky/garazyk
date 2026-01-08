#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseBlob;
@class PDSDatabaseRecord;

extern NSString * const PDSServiceDatabasesErrorDomain;

@interface PDSServiceDatabases : NSObject

@property (nonatomic, strong, readonly) PDSDatabasePool *servicePool;
@property (nonatomic, strong, readonly) PDSDatabasePool *didCachePool;
@property (nonatomic, strong, readonly) PDSDatabasePool *sequencerPool;

+ (instancetype)sharedInstance;

- (instancetype)initWithDirectory:(NSString *)directory 
                     serviceMaxSize:(NSUInteger)serviceMaxSize
                   didCacheMaxSize:(NSUInteger)didCacheMaxSize
                 sequencerMaxSize:(NSUInteger)sequencerMaxSize;

- (BOOL)createAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByDid:(NSString *)did error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByHandle:(NSString *)handle error:(NSError **)error;
- (nullable PDSDatabaseAccount *)getAccountByRefreshToken:(NSString *)refreshToken error:(NSError **)error;
- (BOOL)updateAccount:(PDSDatabaseAccount *)account error:(NSError **)error;
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

- (BOOL)createInviteCode:(NSString *)code 
              forAccount:(NSString *)accountDid
              maxUses:(NSInteger)maxUses
                 error:(NSError **)error;
- (nullable NSString *)getInviteCodeForAccount:(NSString *)accountDid error:(NSError **)error;
- (BOOL)useInviteCode:(NSString *)code error:(NSError **)error;

- (void)cacheDID:(NSString *)did 
        document:(NSDictionary *)document 
      expiresAt:(NSDate *)expiresAt;
- (nullable NSDictionary *)resolveDID:(NSString *)did;

- (void)closeAll;

@end

NS_ASSUME_NONNULL_END

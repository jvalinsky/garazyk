#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;
@class PDSDatabasePool;
@class JWTMinter;

@interface PDSAccountService : NSObject

@property (nonatomic, weak) PDSDatabasePool *databasePool;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong, nullable) JWTMinter *minter;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Account Operations

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                          error:(NSError **)error;

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                 password:(NSString *)password
                                    error:(NSError **)error;

- (nullable NSDictionary *)getAccountForDid:(NSString *)did error:(NSError **)error;

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken
                                       error:(NSError **)error;

- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
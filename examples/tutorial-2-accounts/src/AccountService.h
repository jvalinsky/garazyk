#import <Foundation/Foundation.h>

@class AccountRepository;
@class TutorialJWTMinter;

NS_ASSUME_NONNULL_BEGIN

@interface AccountService : NSObject

- (instancetype)initWithRepository:(AccountRepository *)repository
                            minter:(TutorialJWTMinter *)minter;

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                          error:(NSError **)error;

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

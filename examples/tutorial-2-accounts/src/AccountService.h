#import <Foundation/Foundation.h>
#import "Account.h"
#import "AccountRepository.h"
#import "SimpleJWTMinter.h"

@interface AccountService : NSObject {
}

- (instancetype)initWithRepository:(AccountRepository *)repository
                            minter:(SimpleJWTMinter *)minter;

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                          error:(NSError **)error;

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error;

@end

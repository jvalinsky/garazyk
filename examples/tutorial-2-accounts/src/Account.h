#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Account : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, strong) NSData *passwordHash;
@property (nonatomic, strong) NSData *passwordSalt;
@property (nonatomic, copy, nullable) NSString *accessJwt;
@property (nonatomic, copy, nullable) NSString *refreshJwt;
@property (nonatomic, assign) NSTimeInterval createdAt;

@end

NS_ASSUME_NONNULL_END

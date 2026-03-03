#import <Foundation/Foundation.h>

@interface Account : NSObject {
}

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSData *passwordHash;
@property (nonatomic, copy) NSData *passwordSalt;
@property (nonatomic, copy) NSString *accessJwt;
@property (nonatomic, copy) NSString *refreshJwt;
@property (nonatomic, assign) NSTimeInterval createdAt;

@end

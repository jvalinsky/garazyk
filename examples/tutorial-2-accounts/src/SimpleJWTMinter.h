#import <Foundation/Foundation.h>

@interface SimpleJWTMinter : NSObject {
}

- (instancetype)initWithIssuer:(NSString *)issuer;
- (NSString *)mintAccessTokenForDID:(NSString *)did handle:(NSString *)handle;
- (NSString *)mintRefreshTokenForDID:(NSString *)did handle:(NSString *)handle;

@end

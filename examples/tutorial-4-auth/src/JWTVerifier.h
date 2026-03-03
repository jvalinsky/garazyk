#import <Foundation/Foundation.h>

@interface JWTVerifier : NSObject

- (instancetype)initWithIssuer:(NSString *)issuer publicKey:(NSData *)publicKey;

- (nullable NSDictionary *)verifyToken:(NSString *)token error:(NSError **)error;
- (BOOL)verifySignature:(NSString *)token withPublicKey:(NSData *)publicKey error:(NSError **)error;
- (nullable NSDictionary *)extractPayload:(NSString *)token error:(NSError **)error;

@end

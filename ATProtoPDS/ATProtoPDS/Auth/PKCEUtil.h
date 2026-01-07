#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PKCEUtil : NSObject

+ (NSString *)generateCodeVerifier;
+ (NSString *)generateCodeChallengeWithVerifier:(NSString *)verifier;
+ (BOOL)verifyCodeChallenge:(NSString *)challenge withVerifier:(NSString *)verifier;

@end

NS_ASSUME_NONNULL_END

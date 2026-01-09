#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebAuthnVerifier : NSObject

// Verify a registration response (attestation)
+ (nullable NSDictionary *)verifyRegistrationResponse:(NSDictionary *)response
                                           challenge:(NSData *)expectedChallenge
                                              origin:(NSString *)expectedOrigin
                                               error:(NSError **)error;

// Verify an authentication response (assertion)
+ (BOOL)verifyAssertionResponse:(NSDictionary *)response
                      challenge:(NSData *)expectedChallenge
                         origin:(NSString *)expectedOrigin
                      publicKey:(NSData *)publicKey // COSE key format or Raw Key
                   signCount:(uint32_t)storedSignCount
                    newSignCount:(uint32_t *)outSignCount
                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

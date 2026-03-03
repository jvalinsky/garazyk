#import <Foundation/Foundation.h>

@interface DPoPHandler : NSObject

+ (nullable NSString *)generateDPoPProof:(NSString *)method
                                     uri:(NSString *)uri
                                   nonce:(nullable NSString *)nonce
                              privateKey:(NSData *)privateKey
                               publicKey:(NSData *)publicKey
                                   error:(NSError **)error;

+ (BOOL)verifyDPoPProof:(NSString *)proof
                 method:(NSString *)method
                    uri:(NSString *)uri
              publicKey:(NSData *)publicKey
                  error:(NSError **)error;

+ (nullable NSString *)extractThumbprint:(NSData *)publicKey error:(NSError **)error;

@end

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

@interface DPoPToken : NSObject

@property (nonatomic, copy) NSString *jwt;
@property (nonatomic, copy) NSString *htm;
@property (nonatomic, copy) NSString *htu;
@property (nonatomic, copy) NSString *jti;
@property (nonatomic, copy, nullable) NSString *nonce;
@property (nonatomic, strong) NSDate *iat;
@property (nonatomic, strong, nullable) NSDate *exp;
@property (nonatomic, copy, nullable) NSString *ath;

+ (nullable instancetype)createWithMethod:(NSString *)htm
                                      uri:(NSString *)htu
                                  nonce:(nullable NSString *)nonce
                                  error:(NSError **)error;

- (NSDictionary *)header;
- (NSDictionary *)payload;

@end

@interface DPoPUtil : NSObject

+ (nullable DPoPToken *)createDPoPForMethod:(NSString *)htm
                                         uri:(NSString *)htu
                                      nonce:(nullable NSString *)nonce
                                      error:(NSError **)error;

+ (BOOL)verifyDPoP:(NSString *)dpopJwt
          withPublicKey:(SecKeyRef)publicKey
               method:(NSString *)htm
                  uri:(NSString *)htu
               nonce:(nullable NSString *)nonce
                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

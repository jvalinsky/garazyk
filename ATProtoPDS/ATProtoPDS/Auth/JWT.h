#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const JWTErrorDomain;

typedef NS_ENUM(NSInteger, JWTError) {
    JWTErrorInvalidFormat = 1000,
    JWTErrorInvalidHeader,
    JWTErrorInvalidPayload,
    JWTErrorInvalidSignature,
    JWTErrorTokenExpired,
    JWTErrorTokenNotYetValid,
    JWTErrorInvalidIssuer,
    JWTErrorInvalidSubject,
    JWTErrorInvalidAudience,
    JWTErrorMissingRequiredClaim,
    JWTErrorEncodingFailed,
    JWTErrorDecodingFailed,
    JWTErrorVerificationFailed,
    JWTErrorSigningFailed
};

@interface JWTHeader : NSObject

@property (nonatomic, copy, nullable) NSString *alg;
@property (nonatomic, copy, nullable) NSString *typ;
@property (nonatomic, copy, nullable) NSString *kid;
@property (nonatomic, copy, nullable) NSString *cty;

+ (nullable instancetype)headerFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;
- (NSDictionary *)toDictionary;

@end

@interface JWTPayload : NSObject

@property (nonatomic, copy, nullable) NSString *iss;
@property (nonatomic, copy, nullable) NSString *sub;
@property (nonatomic, copy, nullable) NSString *aud;
@property (nonatomic, strong, nullable) NSDate *exp;
@property (nonatomic, strong, nullable) NSDate *iat;
@property (nonatomic, strong, nullable) NSDate *nbf;
@property (nonatomic, copy, nullable) NSString *jti;
@property (nonatomic, copy, nullable) NSString *did;
@property (nonatomic, copy, nullable) NSString *handle;
@property (nonatomic, copy, nullable) NSString *scope;

+ (nullable instancetype)payloadFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;
- (NSDictionary *)toDictionary;

@end

@interface JWT : NSObject

@property (nonatomic, strong, readonly) JWTHeader *header;
@property (nonatomic, strong, readonly) JWTPayload *payload;
@property (nonatomic, copy, readonly) NSString *rawHeader;
@property (nonatomic, copy, readonly) NSString *rawPayload;
@property (nonatomic, copy, readonly) NSString *signature;
@property (nonatomic, copy, readonly) NSString *encodedSignature;

+ (nullable instancetype)jwtWithToken:(NSString *)token error:(NSError **)error;
+ (nullable instancetype)jwtWithHeader:(JWTHeader *)header
                               payload:(JWTPayload *)payload
                             signature:(NSString *)signature
                                  error:(NSError **)error;

+ (NSString *)base64URLEncodeData:(NSData *)data error:(NSError **)error;
- (NSString *)encodedToken;
- (NSString *)signingInput;

@end

@interface JWTVerifier : NSObject

@property (nonatomic, copy) NSString *expectedIssuer;
@property (nonatomic, copy) NSString *expectedAudience;
@property (nonatomic, strong) NSDate *clockOffset;

- (BOOL)verifyJWT:(JWT *)jwt error:(NSError **)error;
- (BOOL)validateClaims:(JWTPayload *)payload ofJWT:(JWT *)jwt error:(NSError **)error;

@end

@interface JWTMinter : NSObject

@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSString *signingAlgorithm;
@property (nonatomic, assign) NSTimeInterval defaultExpiration;
@property (nonatomic, strong, nullable) NSData *privateKey;

- (NSString *)signPayload:(NSDictionary *)payload error:(NSError **)error;
- (JWT *)mintAccessTokenForDID:(NSString *)did
                        handle:(NSString *)handle
                        scopes:(NSArray<NSString *> *)scopes
                          error:(NSError **)error;
- (JWT *)mintRefreshTokenForDID:(NSString *)did
                         handle:(NSString *)handle
                         scopes:(NSArray<NSString *> *)scopes
                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @protocol PDSKeyPair
 * @brief Abstract representation of a cryptographic key pair
 */
@protocol PDSKeyPair <NSObject>
@property (nonatomic, copy, readonly) NSString *keyID;
@property (nonatomic, copy, readonly) NSString *algorithm;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, assign) BOOL isActive;

/**
 * @brief Export public key as JSON Web Key (JWK)
 */
- (nullable NSDictionary *)publicKeyJWK;

/**
 * @brief Calculate JWK thumbprint (RFC 7638)
 */
- (nullable NSString *)publicKeyThumbprint;
@end

/**
 * @protocol PDSKeyManager
 * @brief Protocol for key management operations
 */
@protocol PDSKeyManager <NSObject>

/**
 * @brief Generate a new key pair
 */
- (nullable id<PDSKeyPair>)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                               keySize:(NSUInteger)keySize
                                                 error:(NSError **)error;

/**
 * @brief Retrieve a specific key pair by ID
 */
- (nullable id<PDSKeyPair>)getKeyPairWithID:(NSString *)keyID error:(NSError **)error;

/**
 * @brief Retrieve the currently active key pair
 */
- (nullable id<PDSKeyPair>)getActiveKeyPair:(NSError **)error;

/**
 * @brief Retrieve all stored key pairs
 */
- (NSArray<id<PDSKeyPair>> *)allKeyPairs:(NSError **)error;

/**
 * @brief Delete a key pair
 */
- (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error;

/**
 * @brief Mark a key pair as active
 */
- (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error;

/**
 * @brief Sign raw data with a specific key
 */
- (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error;

@optional
/**
 * @brief Sign raw data using the active key (convenience method)
 */
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;

/**
 * @brief Sign a JSON payload
 */
- (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error;

/**
 * @brief Sign a string
 */
- (nullable NSString *)signString:(NSString *)string
                         withKeyID:(NSString *)keyID
                             error:(NSError **)error;

/**
 * @brief Export all public keys as JSON Web Key Set (JWKS)
 */
- (NSDictionary *)toJWKS;

/**
 * @brief Export all public keys as array of JWK dictionaries
 */
- (NSArray<NSDictionary *> *)toJWKSArray;

@end

NS_ASSUME_NONNULL_END

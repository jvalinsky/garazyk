#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

extern NSString * const KeyManagerErrorDomain;

typedef NS_ENUM(NSInteger, KeyManagerError) {
    KeyManagerErrorKeyGenerationFailed = 1000,
    KeyManagerErrorKeyNotFound,
    KeyManagerErrorSigningFailed,
    KeyManagerErrorInvalidKeyData,
    KeyManagerErrorExportFailed,
    KeyManagerErrorImportFailed
};

@interface KeyPair : NSObject

@property (nonatomic, copy) NSString *keyID;
@property (nonatomic, copy) NSString *algorithm;
@property (nonatomic, assign) SecKeyRef privateKey;
@property (nonatomic, assign) SecKeyRef publicKey;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) BOOL isActive;

+ (nullable instancetype)keyPairFromPrivateKey:(SecKeyRef)privateKey
                                      publicKey:(SecKeyRef)publicKey
                                        keyID:(NSString *)keyID
                                     algorithm:(NSString *)algorithm;

- (nullable NSDictionary *)publicKeyJWK;
- (nullable NSString *)publicKeyThumbprint;

@end

@interface KeyManager : NSObject

@property (nonatomic, copy) NSString *serviceIdentifier;
@property (nonatomic, assign) SecKeyAlgorithm signingAlgorithm;
@property (nonatomic, copy, nullable) NSString *currentKeyID;
@property (nonatomic, strong, nullable) PDSDatabase *database;

- (nullable instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier;
- (nullable instancetype)initWithDatabase:(PDSDatabase *)database serviceIdentifier:(NSString *)serviceIdentifier;

- (nullable KeyPair *)generateKeyPairWithAlgorithm:(NSString *)algorithm
                                          keySize:(NSUInteger)keySize
                                             error:(NSError **)error;

- (nullable KeyPair *)getKeyPairWithID:(NSString *)keyID error:(NSError **)error;
- (nullable KeyPair *)getActiveKeyPair:(NSError **)error;
- (NSArray<KeyPair *> *)allKeyPairs:(NSError **)error;

- (BOOL)deleteKeyPairWithID:(NSString *)keyID error:(NSError **)error;
- (BOOL)setKeyPairActive:(NSString *)keyID error:(NSError **)error;

- (nullable NSData *)signData:(NSData *)data
                     withKeyID:(NSString *)keyID
                         error:(NSError **)error;

- (nullable NSDictionary *)signPayload:(NSDictionary *)payload
                              withKeyID:(NSString *)keyID
                                  error:(NSError **)error;

- (nullable NSString *)signString:(NSString *)string
                         withKeyID:(NSString *)keyID
                             error:(NSError **)error;

- (BOOL)verifySignature:(NSData *)signature
               forData:(NSData *)data
               withKey:(SecKeyRef)publicKey
                  error:(NSError **)error;

- (NSDictionary *)toJWKS;
- (NSArray<NSDictionary *> *)toJWKSArray;

@end

NS_ASSUME_NONNULL_END

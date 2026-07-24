// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class Secp256k1KeyPair;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSLabelSigningKeyManagerErrorDomain;

typedef NS_ENUM(NSInteger, PDSLabelSigningKeyManagerError) {
    PDSLabelSigningKeyManagerErrorKeyGenerationFailed = 1,
    PDSLabelSigningKeyManagerErrorKeyStorageFailed = 2,
    PDSLabelSigningKeyManagerErrorSigningFailed = 3,
};

@interface PDSLabelSigningKeyManager : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *keyStoragePath;
@property (nonatomic, strong, readonly, nullable) Secp256k1KeyPair *signingKeyPair;
@property (nonatomic, copy, readonly, nullable) NSString *signingKeyDidKey;

+ (instancetype)sharedManager;
- (instancetype)initWithStoragePath:(nullable NSString *)path;
- (BOOL)loadOrGenerateKeyWithError:(NSError **)error;
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error;
- (void)clearKey;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/PDSLabelSigningKeyManager.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Security/PDSKeyEnvelope.h"
#import "Core/ATProtoDataPaths.h"
#import "Debug/GZLogger.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "App/ATProtoServiceConfiguration.h"

#ifdef LINUX
#include <sys/stat.h>
#endif

NSString * const PDSLabelSigningKeyManagerErrorDomain = @"com.garazyk.label.signing";

static NSString *const kLabelSigningKeyFileName = @"label_signing_key.bin";
static PDSLabelSigningKeyManager *_sharedManager = nil;

static NSString *PDSLabelSigningDefaultDataDirectory(void) {
    NSString *envDataDirectory = NSProcessInfo.processInfo.environment[@"PDS_DATA_DIR"];
    if (envDataDirectory.length > 0) return envDataDirectory;
    NSString *homeDir = NSProcessInfo.processInfo.environment[@"HOME"];
    if (homeDir.length > 0) return homeDir;
#if defined(__APPLE__)
    NSArray *urls = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask];
    NSURL *appSupport = urls.count > 0 ? urls[0] : nil;
    return [[appSupport URLByAppendingPathComponent:@"ATProtoPDS"] path];
#else
    return [NSHomeDirectory() stringByAppendingPathComponent:@".local/share/ATProtoPDS"];
#endif
}

static NSString *PDSLabelSigningStorageDirectory(void) {
    NSString *explicitDir = NSProcessInfo.processInfo.environment[@"PDS_LABEL_SIGNING_KEYS_DIR"];
    if (explicitDir.length > 0) return explicitDir;
    ATProtoDataPaths *paths = [ATProtoDataPaths pathsForBaseDirectory:PDSLabelSigningDefaultDataDirectory()];
    return paths.keysDirectory;
}

@interface PDSLabelSigningKeyManager ()
@property (nonatomic, copy, readwrite, nullable) NSString *keyStoragePath;
@property (nonatomic, strong, readwrite, nullable) Secp256k1KeyPair *signingKeyPair;
@property (nonatomic, copy, readwrite, nullable) NSString *signingKeyDidKey;
- (void)ensureSecurePermissionsForPath:(NSString *)path isDirectory:(BOOL)isDir;
- (nullable NSData *)encryptionKeyWithError:(NSError **)error;
@end

@implementation PDSLabelSigningKeyManager

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *dir = PDSLabelSigningStorageDirectory();
        _sharedManager = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:dir];
    });
    return _sharedManager;
}

- (instancetype)initWithStoragePath:(nullable NSString *)path {
    self = [super init];
    if (self) {
        _keyStoragePath = [path copy];
    }
    return self;
}

- (BOOL)loadOrGenerateKeyWithError:(NSError **)error {
    if (self.signingKeyPair) return YES;

    NSString *keyPath = [self keyFilePath];
    if (keyPath) {
        [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
        NSString *directory = [keyPath stringByDeletingLastPathComponent];
        [self ensureSecurePermissionsForPath:directory isDirectory:YES];
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:keyPath]) {
        NSData *keyData = [NSData dataWithContentsOfFile:keyPath];
        NSData *privateKeyData = nil;

        if (keyData.length == 32) {
            privateKeyData = keyData;
            GZ_LOG_INFO(@"Detected legacy unencrypted label signing key.");
            NSData *encKey = [self encryptionKeyWithError:nil];
            if (encKey) {
                NSData *encrypted = [PDSKeyEnvelope seal:privateKeyData withKey:encKey error:nil];
                if (encrypted && [encrypted writeToFile:keyPath atomically:YES]) {
                    GZ_LOG_INFO(@"Migrated label signing key to envelope encryption.");
                    [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
                }
            }
        } else if (keyData.length > 32) {
            NSData *encKey = [self encryptionKeyWithError:error];
            if (encKey) {
                if ([PDSKeyEnvelope isVersionedEnvelope:keyData]) {
                    privateKeyData = [PDSKeyEnvelope openEnvelope:keyData withKey:encKey error:nil];
                } else {
                    privateKeyData = [CryptoUtils decryptData:keyData withKey:encKey];
                }
                if (!privateKeyData) {
                    GZ_LOG_ERROR(@"Failed to decrypt label signing key.");
                    if (error && !*error) {
                        *error = [NSError errorWithDomain:PDSLabelSigningKeyManagerErrorDomain
                                                     code:PDSLabelSigningKeyManagerErrorKeyStorageFailed
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decrypt label signing key"}];
                    }
                    return NO;
                }
            } else {
                return NO;
            }
        }

        if (privateKeyData && privateKeyData.length == 32) {
            NSError *keyError = nil;
            self.signingKeyPair = [[Secp256k1 shared] keyPairFromPrivateKey:privateKeyData error:&keyError];
            if (self.signingKeyPair) {
                self.signingKeyDidKey = self.signingKeyPair.didKeyString;
                GZ_LOG_INFO(@"Loaded label signing key: %@", self.signingKeyDidKey);
                return YES;
            }
            GZ_LOG_ERROR(@"Failed to reconstruct label signing key: %@", keyError);
        }
    }

    NSError *genError = nil;
    self.signingKeyPair = [[Secp256k1 shared] generateKeyPairWithError:&genError];
    if (!self.signingKeyPair) {
        if (error) {
            *error = [NSError errorWithDomain:PDSLabelSigningKeyManagerErrorDomain
                                         code:PDSLabelSigningKeyManagerErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: genError.localizedDescription ?: @"Failed to generate label signing key"}];
        }
        return NO;
    }

    self.signingKeyDidKey = self.signingKeyPair.didKeyString;

    if (keyPath) {
        NSString *directory = [keyPath stringByDeletingLastPathComponent];
        NSError *dirError = nil;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
            NSDictionary *attrs = @{NSFilePosixPermissions: @(0700)};
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                      withIntermediateDirectories:YES
                                                       attributes:attrs
                                                            error:&dirError];
        } else {
            [self ensureSecurePermissionsForPath:directory isDirectory:YES];
        }

        NSData *dataToSave = self.signingKeyPair.privateKey;
        NSData *encKey = [self encryptionKeyWithError:nil];
        if (encKey) {
            NSData *encrypted = [PDSKeyEnvelope seal:dataToSave withKey:encKey error:nil];
            if (encrypted) dataToSave = encrypted;
        }

        if (![dataToSave writeToFile:keyPath atomically:YES]) {
            GZ_LOG_ERROR(@"Failed to write label signing key to: %@", keyPath);
        } else {
            [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
            GZ_LOG_INFO(@"Generated and saved new label signing key: %@", self.signingKeyDidKey);
        }
    }

    return YES;
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    if (!self.signingKeyPair) {
        if (![self loadOrGenerateKeyWithError:error]) return nil;
    }
    if (!data || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSLabelSigningKeyManagerErrorDomain
                                         code:PDSLabelSigningKeyManagerErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty data to sign"}];
        }
        return nil;
    }
    NSData *hash = [CryptoUtils sha256:data];
    NSError *signError = nil;
    NSData *signature = [[Secp256k1 shared] signHash:hash withPrivateKey:self.signingKeyPair.privateKey error:&signError];
    if (!signature) {
        if (error) {
            *error = [NSError errorWithDomain:PDSLabelSigningKeyManagerErrorDomain
                                         code:PDSLabelSigningKeyManagerErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: signError.localizedDescription ?: @"Failed to sign data"}];
        }
        return nil;
    }
    return signature;
}

- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error {
    if (!self.signingKeyPair) {
        if (![self loadOrGenerateKeyWithError:error]) return NO;
    }
    NSData *hash = [CryptoUtils sha256:data];
    return [[Secp256k1 shared] verifySignature:signature forHash:hash withPublicKey:self.signingKeyPair.publicKey error:error];
}

- (void)clearKey {
    self.signingKeyPair = nil;
    self.signingKeyDidKey = nil;
    NSString *keyPath = [self keyFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:keyPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:keyPath error:nil];
    }
}

- (NSString *)keyFilePath {
    if (!self.keyStoragePath) return nil;
    return [self.keyStoragePath stringByAppendingPathComponent:kLabelSigningKeyFileName];
}

- (void)ensureSecurePermissionsForPath:(NSString *)path isDirectory:(BOOL)isDir {
    if (!path) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return;
    short mode = isDir ? 0700 : 0600;
#if defined(__APPLE__)
    NSDictionary *attrs = @{NSFilePosixPermissions: @(mode)};
    NSError *error = nil;
    if (![fm setAttributes:attrs ofItemAtPath:path error:&error]) {
        GZ_LOG_ERROR(@"Failed to set secure permissions (mode %o) on %@: %@", mode, path, error);
    }
#else
    int chmodResult = chmod(path.UTF8String, mode);
    if (chmodResult != 0) {
        GZ_LOG_ERROR(@"Failed to set secure permissions (mode %o) on %@: %d", mode, path, errno);
    }
#endif
}

- (nullable NSData *)encryptionKeyWithError:(NSError **)error {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *secret = config.masterSecret;
    if (secret.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSLabelSigningKeyManagerErrorDomain
                                         code:PDSLabelSigningKeyManagerErrorKeyStorageFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS_MASTER_SECRET not configured"}];
        }
        return nil;
    }
    static uint8_t saltBytes[] = { 0x47, 0x41, 0x52, 0x41, 0x5a, 0x59, 0x4b, 0x5f, 0x4c, 0x42, 0x4c, 0x5f, 0x53, 0x49, 0x47, 0x4e };
    NSData *salt = [NSData dataWithBytes:saltBytes length:sizeof(saltBytes)];
    return [CryptoUtils deriveKeyFromPassword:secret salt:salt];
}

@end

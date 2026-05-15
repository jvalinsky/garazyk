// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLCRotationKeyManager.h"
#import "Auth/Secp256k1.h"
#import "Security/PDSKeyEnvelope.h"
#import "Core/ATProtoDataPaths.h"
#import "Debug/GZLogger.h"
#import "Auth/CryptoUtils.h"
#import "App/ATProtoServiceConfiguration.h"

#ifdef LINUX
#include <sys/stat.h>
#endif

NSString * const PLCRotationKeyManagerErrorDomain = @"com.atproto.plc.rotation";

static NSString *const kRotationKeyFileName = @"plc_rotation_key.bin";
static PLCRotationKeyManager *_sharedManager = nil;

static NSString *PDSDefaultDataDirectory(void) {
    NSString *envDataDirectory = NSProcessInfo.processInfo.environment[@"PDS_DATA_DIR"];
    if (envDataDirectory.length > 0) {
        return envDataDirectory;
    }

    // Also check HOME - commonly set in containers
    NSString *homeDir = NSProcessInfo.processInfo.environment[@"HOME"];
    if (homeDir.length > 0) {
        return homeDir;
    }

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

static NSString *PLCRotationKeyStorageDirectory(void) {
    NSString *explicitKeysDirectory =
        NSProcessInfo.processInfo.environment[@"PDS_PLC_KEYS_DIR"];
    if (explicitKeysDirectory.length > 0) {
        return explicitKeysDirectory;
    }

    ATProtoDataPaths *paths =
        [ATProtoDataPaths pathsForBaseDirectory:PDSDefaultDataDirectory()];
    return paths.keysDirectory;
}

@interface PLCRotationKeyManager ()

@property (nonatomic, copy, readwrite, nullable) NSString *keyStoragePath;
@property (nonatomic, strong, readwrite, nullable) Secp256k1KeyPair *rotationKeyPair;
@property (nonatomic, copy, readwrite, nullable) NSString *rotationKeyDidKey;

- (void)ensureSecurePermissionsForPath:(NSString *)path isDirectory:(BOOL)isDir;
- (nullable NSData *)encryptionKeyWithError:(NSError **)error;

@end

@implementation PLCRotationKeyManager

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *keysDir = PLCRotationKeyStorageDirectory();
        _sharedManager = [[PLCRotationKeyManager alloc] initWithStoragePath:keysDir];
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
    if (self.rotationKeyPair) {
        return YES;
    }
    
    NSString *keyPath = [self keyFilePath];
    
    if (keyPath) {
        // [AUDIT] Proactively secure permissions if the file already exists
        [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
        NSString *directory = [keyPath stringByDeletingLastPathComponent];
        [self ensureSecurePermissionsForPath:directory isDirectory:YES];
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:keyPath]) {
        NSData *keyData = [NSData dataWithContentsOfFile:keyPath];
        NSData *privateKeyData = nil;
        
        if (keyData.length == 32) {
            // Legacy unencrypted key
            privateKeyData = keyData;
            GZ_LOG_INFO(@"Detected legacy unencrypted rotation key.");
            
            // Migrate to envelope encryption if master secret is available
            NSData *encKey = [self encryptionKeyWithError:nil];
            if (encKey) {
                NSData *encrypted = [PDSKeyEnvelope seal:privateKeyData withKey:encKey error:nil];
                if (encrypted) {
                    if ([encrypted writeToFile:keyPath atomically:YES]) {
                        GZ_LOG_INFO(@"Successfully migrated rotation key to envelope encryption.");
                        [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
                    }
                }
            }
        } else if (keyData.length > 32) {
            // Encrypted key — try envelope first, fall back to legacy CBC
            NSData *encKey = [self encryptionKeyWithError:error];
            if (encKey) {
                if ([PDSKeyEnvelope isVersionedEnvelope:keyData]) {
                    privateKeyData = [PDSKeyEnvelope openEnvelope:keyData withKey:encKey error:nil];
                } else {
                    privateKeyData = [CryptoUtils decryptData:keyData withKey:encKey];
                }
                if (!privateKeyData) {
                    GZ_LOG_ERROR(@"Failed to decrypt rotation key. Possible invalid master secret.");
                    if (error && !*error) {
                        *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                                     code:PLCRotationKeyManagerErrorKeyStorageFailed
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decrypt rotation key"}];
                    }
                    return NO;
                }
            } else {
                return NO; // Error already set by encryptionKeyWithError:
            }
        }
        
        if (privateKeyData && privateKeyData.length == 32) {
            NSError *keyError = nil;
            self.rotationKeyPair = [[Secp256k1 shared] keyPairFromPrivateKey:privateKeyData error:&keyError];
            if (self.rotationKeyPair) {
                self.rotationKeyDidKey = self.rotationKeyPair.didKeyString;
                GZ_LOG_INFO(@"Loaded rotation key: %@", self.rotationKeyDidKey);
                return YES;
            }
            GZ_LOG_ERROR(@"Failed to reconstruct rotation key: %@", keyError);
        }
    }
    
    NSError *genError = nil;
    self.rotationKeyPair = [[Secp256k1 shared] generateKeyPairWithError:&genError];
    if (!self.rotationKeyPair) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorKeyGenerationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: genError.localizedDescription ?: @"Failed to generate rotation key"}];
        }
        return NO;
    }
    
    self.rotationKeyDidKey = self.rotationKeyPair.didKeyString;
    
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
        
        NSData *dataToSave = self.rotationKeyPair.privateKey;
        NSData *encKey = [self encryptionKeyWithError:nil];
        if (encKey) {
            NSData *encrypted = [PDSKeyEnvelope seal:dataToSave withKey:encKey error:nil];
            if (encrypted) {
                dataToSave = encrypted;
            }
        }
        
        if (![dataToSave writeToFile:keyPath atomically:YES]) {
            GZ_LOG_ERROR(@"Failed to write rotation key to: %@", keyPath);
        } else {
            [self ensureSecurePermissionsForPath:keyPath isDirectory:NO];
            GZ_LOG_INFO(@"Generated and saved new PLC rotation key: %@", self.rotationKeyDidKey);
        }
    }
    
    return YES;
}

- (BOOL)signHash:(NSData *)hash result:(NSData * _Nullable * _Nullable)result error:(NSError **)error {
    if (!self.rotationKeyPair) {
        if (![self loadOrGenerateKeyWithError:error]) {
            return NO;
        }
    }
    
    if (!hash || hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorInvalidKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid hash (must be 32 bytes)"}];
        }
        return NO;
    }
    
    NSError *signError = nil;
    NSData *signature = [[Secp256k1 shared] signHash:hash withPrivateKey:self.rotationKeyPair.privateKey error:&signError];
    if (!signature) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorKeyStorageFailed
                                     userInfo:@{NSLocalizedDescriptionKey: signError.localizedDescription ?: @"Failed to sign hash"}];
        }
        return NO;
    }
    
    if (result) {
        *result = signature;
    }
    return YES;
}

- (void)clearKey {
    self.rotationKeyPair = nil;
    self.rotationKeyDidKey = nil;
    
    NSString *keyPath = [self keyFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:keyPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:keyPath error:nil];
    }
}

- (NSString *)keyFilePath {
    if (!self.keyStoragePath) {
        return nil;
    }
    return [self.keyStoragePath stringByAppendingPathComponent:kRotationKeyFileName];
}

- (void)ensureSecurePermissionsForPath:(NSString *)path isDirectory:(BOOL)isDir {
    if (!path) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return;

    short mode = isDir ? 0700 : 0600;
    NSDictionary *attrs = nil;

#if defined(__APPLE__)
    attrs = @{NSFilePosixPermissions: @(mode)};
#else
    // Linux: use chmod directly via system call
    int chmodResult = chmod(path.UTF8String, mode);
    if (chmodResult != 0) {
        GZ_LOG_ERROR(@"Failed to set secure permissions (mode %o) on %@: %d", mode, path, errno);
    } else {
        GZ_LOG_DEBUG(@"Set secure permissions (mode %o) on %@", mode, path);
    }
    return;
#endif

    NSError *error = nil;
    if (![fm setAttributes:attrs ofItemAtPath:path error:&error]) {
        GZ_LOG_ERROR(@"Failed to set secure permissions (mode %o) on %@: %@", mode, path, error);
    } else {
        GZ_LOG_DEBUG(@"Set secure permissions (mode %o) on %@", mode, path);
    }
}

- (nullable NSData *)encryptionKeyWithError:(NSError **)error {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *secret = config.masterSecret;
    if (secret.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PLCRotationKeyManagerErrorDomain
                                         code:PLCRotationKeyManagerErrorKeyStorageFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"PDS_MASTER_SECRET not configured"}];
        }
        return nil;
    }
    
    static uint8_t saltBytes[] = { 0x41, 0x54, 0x50, 0x52, 0x4f, 0x54, 0x4f, 0x5f, 0x50, 0x44, 0x53, 0x5f, 0x4b, 0x45, 0x59, 0x53 };
    NSData *salt = [NSData dataWithBytes:saltBytes length:sizeof(saltBytes)];
    
    return [CryptoUtils deriveKeyFromPassword:secret salt:salt];
}

@end

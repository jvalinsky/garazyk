//
//  PDSOpenSSLKeyManager.m
//  ATProtoPDS
//

#import "PDSOpenSSLKeyManager.h"

#import <CommonCrypto/CommonDigest.h>

#import "Auth/Secp256k1.h"

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

NSString * const PDSOpenSSLKeyManagerErrorDomain = @"com.atproto.pds.opensslkeymanager";

@interface PDSOpenSSLKeyManager ()
@property (nonatomic, strong, nullable) NSData *memoryKeyData;
@end

@interface PDSOpenSSLKeyManager ()
@property (nonatomic, copy, readwrite) NSString *keyManagerId;
@end

@implementation PDSOpenSSLKeyManager

- (instancetype)initWithDid:(NSString *)did keystorePath:(NSString *)keystorePath {
    self = [super init];
    if (self) {
        _did = [did copy];
        _keystorePath = [keystorePath copy];
    }
    return self;
}

- (BOOL)generateSigningKeyWithError:(NSError **)error {
    NSError *genError = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&genError];
    if (!keyPair) {
        if (error) {
            *error = genError;
        }
        return NO;
    }
    return [self importSigningKey:keyPair.privateKey error:error];
}

- (BOOL)importSigningKey:(NSData *)privateKey error:(NSError **)error {
    if (privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key must be 32 bytes (secp256k1)"}];
        }
        return NO;
    }

    NSError *writeError = nil;
    if (![self writePrivateKey:privateKey error:&writeError]) {
        // Keep service available when persistent storage is not writable.
        self.memoryKeyData = [privateKey copy];
        return YES;
    }

    self.memoryKeyData = nil;
    return YES;
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    NSData *privateKey = [self loadPrivateKeyWithError:error];
    if (!privateKey) {
        return nil;
    }

    uint8_t hash[CC_SHA256_DIGEST_LENGTH] = {0};
    if (!CC_SHA256(data.bytes, (CC_LONG)data.length, hash)) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to hash signing payload"}];
        }
        return nil;
    }

    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    return [[Secp256k1 shared] signHash:hashData withPrivateKey:privateKey error:error];
}

- (nullable NSData *)publicSigningKeyWithError:(NSError **)error {
    NSData *privateKey = [self loadPrivateKeyWithError:error];
    if (!privateKey) {
        return nil;
    }

    Secp256k1KeyPair *pair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:error];
    if (!pair) {
        return nil;
    }
    return pair.compressedPublicKey;
}

- (nullable NSString *)didKeyStringWithError:(NSError **)error {
    NSData *privateKey = [self loadPrivateKeyWithError:error];
    if (!privateKey) {
        return nil;
    }

    Secp256k1KeyPair *pair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKey error:error];
    if (!pair) {
        return nil;
    }
    return pair.didKeyString;
}

- (nullable NSData *)loadPrivateKeyWithError:(NSError **)error {
    if (self.memoryKeyData.length == 32) {
        return self.memoryKeyData;
    }

    NSData *privateKey = [NSData dataWithContentsOfFile:[self privateKeyPath]
                                                options:0
                                                  error:error];
    if (!privateKey) {
        if (error && *error == nil) {
            *error = [NSError errorWithDomain:PDSOpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Signing key not found"}];
        }
        return nil;
    }

    if (privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:PDSOpenSSLKeyManagerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Stored signing key has invalid length"}];
        }
        return nil;
    }

    return privateKey;
}

- (BOOL)writePrivateKey:(NSData *)privateKey error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:self.keystorePath
       withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions: @0700}
                             error:error]) {
        return NO;
    }

    NSString *targetPath = [self privateKeyPath];
    NSString *tmpPath = [self.keystorePath stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.tmp", [[NSUUID UUID] UUIDString]]];

    int fd = open([tmpPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd == -1) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return NO;
    }

    ssize_t written = write(fd, privateKey.bytes, (size_t)privateKey.length);
    int writeErrno = errno;
    (void)fsync(fd);
    close(fd);

    if (written != (ssize_t)privateKey.length) {
        unlink([tmpPath fileSystemRepresentation]);
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:writeErrno userInfo:nil];
        }
        return NO;
    }

    if (rename([tmpPath fileSystemRepresentation], [targetPath fileSystemRepresentation]) != 0) {
        int renameErrno = errno;
        unlink([tmpPath fileSystemRepresentation]);
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:renameErrno userInfo:nil];
        }
        return NO;
    }

    [fm setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:targetPath error:nil];
    return YES;
}

- (NSString *)privateKeyPath {
    NSString *sanitizedDid = [[self.did stringByReplacingOccurrencesOfString:@":" withString:@"_"]
                           stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *fileName = [NSString stringWithFormat:@"%@.secp256k1.key", sanitizedDid];
    return [self.keystorePath stringByAppendingPathComponent:fileName];
}

@end

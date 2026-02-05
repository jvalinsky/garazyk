/*!
 @file JWTSigningKeyStore.m
 */

#import "Auth/JWTSigningKeyStore.h"

#import "Auth/Secp256k1.h"
#import "Debug/PDSLogger.h"

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

@implementation JWTSigningKeyStore

+ (NSString *)privateKeyPathForDataDirectory:(NSString *)dataDirectory {
    NSString *envPath = [[NSProcessInfo processInfo] environment][@"PDS_JWT_PRIVATE_KEY_PATH"];
    if (envPath.length > 0) {
        return envPath;
    }

    NSString *keysDir = [dataDirectory stringByAppendingPathComponent:@"keys"];
    return [keysDir stringByAppendingPathComponent:@"jwt_secp256k1_private.key"];
}

+ (BOOL)writePrivateKey:(NSData *)privateKey toPath:(NSString *)path error:(NSError **)error {
    if (privateKey.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidPrivateKey
                                     userInfo:@{NSLocalizedDescriptionKey: @"Private key must be 32 bytes"}];
        }
        return NO;
    }

    NSString *directory = [path stringByDeletingLastPathComponent];
    NSError *dirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES
                                                    attributes:@{NSFilePosixPermissions: @0700}
                                                         error:&dirError]) {
        if (error) *error = dirError;
        return NO;
    }

    NSString *tmpPath = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@".jwtkey.%@.tmp", [[NSUUID UUID] UUIDString]]];
    int fd = open([tmpPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd == -1) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return NO;
    }

    ssize_t written = write(fd, privateKey.bytes, (size_t)privateKey.length);
    int savedErrno = errno;
    (void)fsync(fd);
    close(fd);
    if (written != (ssize_t)privateKey.length) {
        unlink([tmpPath fileSystemRepresentation]);
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil];
        }
        return NO;
    }

    if (rename([tmpPath fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
        NSError *moveError = nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:path]) {
            [fm removeItemAtPath:path error:nil];
        }
        if (![fm moveItemAtPath:tmpPath toPath:path error:&moveError]) {
            unlink([tmpPath fileSystemRepresentation]);
            if (error) *error = moveError;
            return NO;
        }
    }

    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:path
                                            error:nil];
    return YES;
}

+ (nullable Secp256k1KeyPair *)loadOrCreateKeyPairForDataDirectory:(NSString *)dataDirectory
                                                             error:(NSError **)error {
    NSString *path = [self privateKeyPathForDataDirectory:dataDirectory];

    NSError *readError = nil;
    NSData *privateKeyData = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (privateKeyData) {
        if (privateKeyData.length != 32) {
            PDS_LOG_AUTH_ERROR(@"JWT signing key at %@ has invalid length (%lu bytes); refusing to overwrite", path, (unsigned long)privateKeyData.length);
            if (error) {
                *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                             code:Secp256k1ErrorInvalidPrivateKey
                                         userInfo:@{NSLocalizedDescriptionKey: @"JWT signing key file has invalid length"}];
            }
            return [[Secp256k1 shared] generateKeyPairWithError:nil];
        }

        NSError *keyError = nil;
        Secp256k1KeyPair *keyPair = [Secp256k1KeyPair keyPairWithPrivateKey:privateKeyData error:&keyError];
        if (!keyPair) {
            PDS_LOG_AUTH_ERROR(@"Failed to load JWT signing key from %@: %@", path, keyError.localizedDescription ?: @"unknown error");
            if (error) *error = keyError;
            return [[Secp256k1 shared] generateKeyPairWithError:nil];
        }

        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                         ofItemAtPath:path
                                                error:nil];
        return keyPair;
    }

    if (readError && readError.code != NSFileReadNoSuchFileError) {
        PDS_LOG_AUTH_WARN(@"Unable to read JWT signing key from %@: %@", path, readError.localizedDescription ?: @"unknown error");
    }

    NSError *genError = nil;
    Secp256k1KeyPair *generated = [[Secp256k1 shared] generateKeyPairWithError:&genError];
    if (!generated) {
        if (error) *error = genError;
        return nil;
    }

    NSError *writeError = nil;
    if (![self writePrivateKey:generated.privateKey toPath:path error:&writeError]) {
        PDS_LOG_AUTH_ERROR(@"Failed to persist JWT signing key to %@: %@", path, writeError.localizedDescription ?: @"unknown error");
        if (error) *error = writeError;
        return generated;
    }

    PDS_LOG_AUTH_INFO(@"Generated and persisted new JWT signing key at %@", path);
    return generated;
}

@end


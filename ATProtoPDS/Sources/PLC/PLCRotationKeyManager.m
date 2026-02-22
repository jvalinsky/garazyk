#import "PLCRotationKeyManager.h"
#import "Auth/Secp256k1.h"
#import "Debug/PDSLogger.h"
#import "App/PDSConfiguration.h"

NSString * const PLCRotationKeyManagerErrorDomain = @"com.atproto.plc.rotation";

static NSString *const kRotationKeyFileName = @"plc_rotation_key.bin";
static PLCRotationKeyManager *_sharedManager = nil;

@interface PLCRotationKeyManager ()

@property (nonatomic, copy, readwrite, nullable) NSString *keyStoragePath;
@property (nonatomic, strong, readwrite, nullable) Secp256k1KeyPair *rotationKeyPair;
@property (nonatomic, copy, readwrite, nullable) NSString *rotationKeyDidKey;

@end

@implementation PLCRotationKeyManager

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *defaultPath = [PDSConfiguration defaultDataDirectory];
        _sharedManager = [[PLCRotationKeyManager alloc] initWithStoragePath:defaultPath];
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
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:keyPath]) {
        NSData *keyData = [NSData dataWithContentsOfFile:keyPath];
        if (keyData.length == 32) {
            NSError *keyError = nil;
            self.rotationKeyPair = [[Secp256k1 shared] keyPairFromPrivateKey:keyData error:&keyError];
            if (self.rotationKeyPair) {
                self.rotationKeyDidKey = self.rotationKeyPair.didKeyString;
                PDS_LOG_INFO(@"Loaded existing PLC rotation key: %@", self.rotationKeyDidKey);
                return YES;
            }
            PDS_LOG_ERROR(@"Failed to reconstruct rotation key from stored data: %@", keyError);
        }
        PDS_LOG_ERROR(@"Invalid rotation key file size: %lu bytes", (unsigned long)keyData.length);
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
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&dirError];
        }
        
        if (![self.rotationKeyPair.privateKey writeToFile:keyPath atomically:YES]) {
            PDS_LOG_ERROR(@"Failed to write rotation key to: %@", keyPath);
        } else {
            PDS_LOG_INFO(@"Generated and saved new PLC rotation key: %@", self.rotationKeyDidKey);
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

@end

#import "PDSBiometricKeychain.h"
#import <Security/SecItem.h>
#import <Security/SecAccessControl.h>
#import <CommonCrypto/CommonKeyDerivation.h>

NSString * const PDSBiometricKeychainErrorDomain = @"com.september.biometric.keychain";

static NSString * const kKeyType = @"september.signing.key";

@interface PDSBiometricKeychain ()
@property (nonatomic, copy, readwrite) NSString *serviceName;
@property (nonatomic, copy, readwrite) NSString *accessGroup;
@property (nonatomic, assign, readwrite) BOOL useBiometrics;
@end

@implementation PDSBiometricKeychain

+ (instancetype)sharedInstance {
    static PDSBiometricKeychain *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSBiometricKeychain alloc] initWithServiceName:@"com.september.pds"
                                                       accessGroup:nil
                                                     useBiometrics:YES];
    });
    return shared;
}

- (instancetype)initWithServiceName:(NSString *)serviceName
                        accessGroup:(NSString *)accessGroup
                      useBiometrics:(BOOL)useBiometrics {
    self = [super init];
    if (self) {
        _serviceName = [serviceName copy];
        _accessGroup = [accessGroup copy];
        _useBiometrics = useBiometrics;
    }
    return self;
}

- (BOOL)storeKey:(NSData *)keyData
        forAccount:(NSString *)account
             error:(NSError **)error {
    if (!keyData || keyData.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBiometricKeychainErrorDomain
                                         code:PDSBiometricKeychainErrorEncodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Key data is empty"}];
        }
        return NO;
    }

    NSMutableDictionary *query = [self baseQueryForAccount:account];
    query[(__bridge id)kSecValueData] = keyData;
    query[(__bridge id)kSecAttrAccessible] = [self accessibilityValue];

    if (self.useBiometrics) {
        SecAccessControlRef accessControl = [self createAccessControlWithError:error];
        if (!accessControl) {
            return NO;
        }
        query[(__bridge id)kSecAttrAccessControl] = (__bridge id)accessControl;
        CFRelease(accessControl);
    }

    if (self.accessGroup) {
        query[(__bridge id)kSecAttrAccessGroup] = self.accessGroup;
    }

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);

    if (status == errSecDuplicateItem) {
        SecItemDelete((__bridge CFDictionaryRef)query);
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }

    if (status != errSecSuccess) {
        if (error) {
            *error = [self errorForOSStatus:status];
        }
        return NO;
    }

    return YES;
}

- (NSData *)retrieveKeyForAccount:(NSString *)account
                            error:(NSError **)error {
    NSMutableDictionary *query = [self baseQueryForAccount:account];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    if (self.useBiometrics) {
        query[(__bridge id)kSecUseAuthenticationContext] = [self createAuthenticationContextWithError:error];
        if (!query[(__bridge id)kSecUseAuthenticationContext]) {
            return nil;
        }
    }

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status != errSecSuccess) {
        if (error) {
            *error = [self errorForOSStatus:status];
        }
        if (result) {
            CFRelease(result);
        }
        return nil;
    }

    NSData *keyData = (__bridge_transfer NSData *)result;
    return keyData;
}

- (BOOL)deleteKeyForAccount:(NSString *)account
                      error:(NSError **)error {
    NSMutableDictionary *query = [self baseQueryForAccount:account];

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) {
            *error = [self errorForOSStatus:status];
        }
        return NO;
    }

    return YES;
}

- (BOOL)keyExistsForAccount:(NSString *)account {
    NSMutableDictionary *query = [self baseQueryForAccount:account];
    query[(__bridge id)kSecReturnData] = @NO;

    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

- (LAContext *)createAuthenticationContextWithError:(NSError **)error {
    LAContext *context = [[LAContext alloc] init];
    context.localizedCancelTitle = @"Cancel";
    context.localizedFallbackTitle = @"Use Passcode";

    if (@available(macOS 12.0, *)) {
        if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil]) {
            return context;
        }
    }

    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:nil]) {
        return context;
    }

    if (error) {
        *error = [NSError errorWithDomain:PDSBiometricKeychainErrorDomain
                                     code:PDSBiometricKeychainErrorBiometryNotAvailable
                                 userInfo:@{NSLocalizedDescriptionKey: @"Biometric authentication is not available"}];
    }

    return nil;
}

- (BOOL)upgradeExistingKeysWithAccounts:(NSArray<NSString *> *)accounts
                                  error:(NSError **)error {
    BOOL allUpgraded = YES;

    for (NSString *account in accounts) {
        if (![self keyExistsForAccount:account]) {
            continue;
        }

        NSMutableDictionary *oldQuery = [self baseQueryForAccount:account];
        oldQuery[(__bridge id)kSecReturnData] = @YES;

        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)oldQuery, &result);

        if (status != errSecSuccess || !result) {
            allUpgraded = NO;
            continue;
        }

        NSData *keyData = (__bridge_transfer NSData *)result;

        SecItemDelete((__bridge CFDictionaryRef)oldQuery);

        if (![self storeKey:keyData forAccount:account error:error]) {
            allUpgraded = NO;
        }
    }

    return allUpgraded;
}

- (BOOL)isBiometryAvailable {
    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;

    if (@available(macOS 12.0, *)) {
        return [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
    }

    return [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error];
}

- (NSString *)biometryTypeString {
    LAContext *context = [[LAContext alloc] init];
    LABiometryType biometryType = context.biometryType;

    switch (biometryType) {
        case LABiometryTypeFaceID:
            return @"Face ID";
        case LABiometryTypeTouchID:
            return @"Touch ID";
        default:
            return @"Passcode";
    }
}

#pragma mark - Private Methods

- (NSMutableDictionary *)baseQueryForAccount:(NSString *)account {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = self.serviceName;
    query[(__bridge id)kSecAttrAccount] = account;
    query[(__bridge id)kSecAttrType] = kKeyType;
    return query;
}

- (id)accessibilityValue {
    if (self.useBiometrics) {
        return (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    }
    return (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
}

- (SecAccessControlRef)createAccessControlWithError:(NSError **)error {
    SecAccessControlCreateFlags flags;

    if (@available(macOS 12.0, *)) {
        flags = kSecAccessControlBiometryCurrentSet;
    } else {
        flags = kSecAccessControlBiometryAny;
    }

    CFErrorRef cfError = NULL;
    SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                                                         kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                         flags,
                                                                         &cfError);

    if (cfError) {
        if (error) {
            *error = (__bridge_transfer NSError *)cfError;
        }
        return NULL;
    }

    return accessControl;
}

- (NSError *)errorForOSStatus:(OSStatus)status {
    NSString *message = @"Unknown error";
    NSInteger code = PDSBiometricKeychainErrorAuthFailed;

    switch (status) {
        case errSecAuthFailed:
            message = @"Authentication failed";
            code = PDSBiometricKeychainErrorAuthFailed;
            break;
        case errSecItemNotFound:
            message = @"Key not found";
            code = PDSBiometricKeychainErrorKeyNotFound;
            break;
        case errSecDuplicateItem:
            message = @"Key already exists";
            code = PDSBiometricKeychainErrorKeyAlreadyExists;
            break;
        case errSecParam:
            message = @"Invalid parameter";
            code = PDSBiometricKeychainErrorEncodingFailed;
            break;
        case errSecNotAvailable:
            message = @"Biometry not available";
            code = PDSBiometricKeychainErrorBiometryNotAvailable;
            break;
        default:
            message = [NSString stringWithFormat:@"Security error: %d", (int)status];
            break;
    }

    return [NSError errorWithDomain:PDSBiometricKeychainErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end

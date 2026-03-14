#import "PDSBiometricKeychain.h"
#import <Security/SecItem.h>
#import <Security/SecAccessControl.h>
#import <CommonCrypto/CommonKeyDerivation.h>

NSString * const PDSBiometricKeychainErrorDomain = @"com.september.biometric.keychain";

static NSString * const kKeyLabel = @"september.signing.key";

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

    NSMutableDictionary *addQuery = [self baseQueryForAccount:account];
    addQuery[(__bridge id)kSecValueData] = keyData;

    if (self.useBiometrics) {
        // kSecAttrAccessControl encodes the accessibility protection — do not
        // also set kSecAttrAccessible, which would conflict.
        SecAccessControlRef accessControl = [self createAccessControlWithError:error];
        if (!accessControl) {
            return NO;
        }
        addQuery[(__bridge id)kSecAttrAccessControl] = (__bridge_transfer id)accessControl;
    } else {
        addQuery[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    }

    if (self.accessGroup) {
        addQuery[(__bridge id)kSecAttrAccessGroup] = self.accessGroup;
    }

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);

    if (status == errSecDuplicateItem) {
        // Use SecItemUpdate (atomic) rather than delete + re-add (racy).
        NSMutableDictionary *searchQuery = [self baseQueryForAccount:account];
        if (self.accessGroup) {
            searchQuery[(__bridge id)kSecAttrAccessGroup] = self.accessGroup;
        }
        NSDictionary *updateAttrs = @{ (__bridge id)kSecValueData: keyData };
        status = SecItemUpdate((__bridge CFDictionaryRef)searchQuery,
                               (__bridge CFDictionaryRef)updateAttrs);
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
    // Skip biometric UI — we only want to know if the item exists.
    query[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUISkip;

    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

- (LAContext *)createAuthenticationContextWithError:(NSError **)error {
    LAContext *context = [[LAContext alloc] init];
    context.localizedCancelTitle = @"Cancel";
    context.localizedFallbackTitle = @"Use Passcode";

    // LAPolicyDeviceOwnerAuthenticationWithBiometrics is available since macOS 10.12.
    // The deployment target is macOS 14+, so no availability guard is needed.
    NSError *evalError = nil;
    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                             error:&evalError]) {
        return context;
    }

    // Fall back to passcode if biometrics are unavailable.
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
        if (self.useBiometrics) {
            NSError *ctxError = nil;
            LAContext *ctx = [self createAuthenticationContextWithError:&ctxError];
            if (ctx) {
                oldQuery[(__bridge id)kSecUseAuthenticationContext] = ctx;
            }
        }

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
    return [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                                error:&error];
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
    query[(__bridge id)kSecClass]        = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService]  = self.serviceName;
    query[(__bridge id)kSecAttrAccount]  = account;
    // kSecAttrLabel accepts an NSString and is used to tag / identify items.
    // kSecAttrType expects a FourCharCode (CFNumberRef) and must not be an NSString.
    query[(__bridge id)kSecAttrLabel]    = kKeyLabel;
    return query;
}

- (id)accessibilityValue {
    if (self.useBiometrics) {
        return (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    }
    return (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
}

- (SecAccessControlRef)createAccessControlWithError:(NSError **)error {
    // kSecAccessControlBiometryCurrentSet invalidates the key when enrolled
    // biometrics change — available since macOS 10.13. The deployment target
    // is macOS 14+, so no availability guard is needed.
    CFErrorRef cfError = NULL;
    SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlBiometryCurrentSet,
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

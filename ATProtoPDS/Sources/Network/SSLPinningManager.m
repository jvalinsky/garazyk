#ifdef GNUSTEP
#import "Compat/GNUstepCompat.h"
#endif

#import "SSLPinningManager.h"
#import "App/PDSConfiguration.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <stdint.h>
#import "Debug/PDSLogger.h"

NSString *const SSLPinningErrorDomain = @"com.atproto.pds.sslpinning";

@interface SSLPinningManager ()

@property (nonatomic, assign) BOOL pinningEnabled;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSData *> *> *pinnedKeys;

@end

@implementation SSLPinningManager

+ (instancetype)sharedManager {
    static SSLPinningManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Use configuration to determine if pinning is enabled
        PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
        shared = [[SSLPinningManager alloc] initWithPinningEnabled:config.sslPinningEnabled];
    });
    return shared;
}

- (instancetype)initWithPinningEnabled:(BOOL)pinningEnabled {
    self = [super init];
    if (self) {
        _pinningEnabled = pinningEnabled;
        _pinnedKeys = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addPinnedPublicKey:(NSData *)publicKeyData forDomain:(NSString *)domain {
    if (!domain || !publicKeyData) return;

    NSMutableArray<NSData *> *keys = self.pinnedKeys[domain];
    if (!keys) {
        keys = [NSMutableArray array];
        self.pinnedKeys[domain] = keys;
    }

    // Avoid duplicates
    if (![keys containsObject:publicKeyData]) {
        [keys addObject:publicKeyData];
    }
}

- (void)removePinnedKeysForDomain:(NSString *)domain {
    if (domain) {
        [self.pinnedKeys removeObjectForKey:domain];
    }
}

- (NSURLSession *)createSessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    return [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
}

- (BOOL)validateChallenge:(NSURLAuthenticationChallenge *)challenge forDomain:(NSString *)domain {
    if (!self.pinningEnabled) {
        // If pinning is disabled, use default validation
        return [challenge.sender respondsToSelector:@selector(performDefaultHandlingForAuthenticationChallenge:)];
    }

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
        if (!serverTrust) return NO;

        return [self validateServerTrust:serverTrust forDomain:domain];
    }

    return NO;
}

- (BOOL)validateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
    if (!self.pinningEnabled) return YES;

    NSArray<NSData *> *pinnedKeys = self.pinnedKeys[domain];
    if (!pinnedKeys || pinnedKeys.count == 0) {
        // No pinned keys for this domain - allow connection but log warning
        PDS_LOG_HTTP_WARN(@"SSLPinning: No pinned keys configured for domain %@", domain);
        return YES;
    }

    // Get the certificate chain
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    if (certificateCount == 0) return NO;

    // Get the leaf certificate (server certificate)
    SecCertificateRef leafCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0);
    if (!leafCertificate) return NO;

    // Extract public key from certificate
    SecKeyRef publicKey = [self publicKeyFromCertificate:leafCertificate];
    if (!publicKey) return NO;

    // Get public key data
    NSData *publicKeyData = [self dataFromPublicKey:publicKey];
    if (!publicKeyData) {
        CFRelease(publicKey);
        return NO;
    }

    // Check if the public key matches any pinned key
    for (NSData *pinnedKeyData in pinnedKeys) {
        if ([publicKeyData isEqualToData:pinnedKeyData]) {
            CFRelease(publicKey);
            return YES;
        }
    }

    // Public key not pinned
    CFRelease(publicKey);
    return NO;
}

- (SecKeyRef)publicKeyFromCertificate:(SecCertificateRef)certificate {
    if (!certificate) return NULL;

    // Create trust reference
    SecTrustRef trust = NULL;
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    OSStatus status = SecTrustCreateWithCertificates(certificate, policy, &trust);

    if (status != errSecSuccess || !trust) {
        if (policy) CFRelease(policy);
        return NULL;
    }

    // Evaluate trust to populate certificate chain
    SecTrustResultType trustResult;
    status = SecTrustEvaluate(trust, &trustResult);
    if (status != errSecSuccess) {
        CFRelease(trust);
        CFRelease(policy);
        return NULL;
    }

    // Get public key
    SecKeyRef publicKey = SecTrustCopyKey(trust);

    CFRelease(trust);
    CFRelease(policy);

    return publicKey;
}

- (NSData *)dataFromPublicKey:(SecKeyRef)publicKey {
    if (!publicKey) return nil;

    CFErrorRef error = NULL;
    CFDataRef keyData = SecKeyCopyExternalRepresentation(publicKey, &error);
    if (!keyData) {
        if (error) CFRelease(error);
        return nil;
    }

    return (__bridge_transfer NSData *)keyData;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSString *host = challenge.protectionSpace.host;

        if ([self validateChallenge:challenge forDomain:host]) {
            // Create credential with the server trust
            NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        } else {
            // Pinning validation failed
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        }
    } else {
        // For other authentication methods, use default handling
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end
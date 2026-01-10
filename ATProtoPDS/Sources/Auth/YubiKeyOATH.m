#import "Auth/YubiKeyOATH.h"
#import "Auth/TOTPGenerator.h"
#import <os/log.h>

NSString * const YubiKeyOATHErrorDomain = @"com.atproto.pds.yubikey.oath";

@interface YubiKeyOATHManager ()

@property (nonatomic, assign, readwrite) YubiKeyConnectionState connectionState;
@property (nonatomic, copy, readwrite, nullable) NSString *connectedKeySerial;
@property (nonatomic, strong) os_log_t log;

@end

@implementation YubiKeyOATHManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _connectionState = YubiKeyConnectionStateDisconnected;
        _log = os_log_create("com.atproto.pds", "yubikey");
    }
    return self;
}

- (BOOL)isHardwareAvailable {
    return NO;
}

#pragma mark - Connection Management

- (void)startScanning {
    os_log_info(_log, "YubiKey OATH scanning started (software-only mode)");
    self.connectionState = YubiKeyConnectionStateDisconnected;
}

- (void)stopScanning {
    os_log_info(_log, "YubiKey OATH scanning stopped");
    self.connectionState = YubiKeyConnectionStateDisconnected;
    self.connectedKeySerial = nil;
}

- (void)refreshConnection {
    os_log_info(_log, "YubiKey OATH connection refresh requested (software-only mode)");
    self.connectionState = YubiKeyConnectionStateDisconnected;
    self.connectedKeySerial = nil;
}

#pragma mark - YubiKeyOATH Protocol

- (nullable NSString *)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error {
    os_log_debug(_log, "Generating TOTP (software fallback)");
    return [self generateSoftwareTOTPToken:secret counter:counter error:error];
}

- (BOOL)setOATHSecret:(NSData *)secret name:(NSString *)name error:(NSError **)error {
    os_log_info(_log, "Set OATH secret requested for '%{public}@' (software-only mode)", name);
    if (error) {
        *error = [NSError errorWithDomain:YubiKeyOATHErrorDomain
                                    code:YubiKeyOATHErrorNotImplemented
                                userInfo:@{NSLocalizedDescriptionKey: @"Hardware YubiKey OATH not available. Install YubiKit SDK for hardware support."}];
    }
    return NO;
}

#pragma mark - Credential Management

- (nullable NSArray<NSDictionary *> *)listCredentialsWithError:(NSError **)error {
    os_log_debug(_log, "List credentials requested (software-only mode)");
    return @[];
}

- (BOOL)deleteCredentialWithName:(NSString *)name error:(NSError **)error {
    os_log_info(_log, "Delete credential '%{public}@' requested (software-only mode)", name);
    if (error) {
        *error = [NSError errorWithDomain:YubiKeyOATHErrorDomain
                                    code:YubiKeyOATHErrorNotImplemented
                                userInfo:@{NSLocalizedDescriptionKey: @"Hardware YubiKey OATH not available"}];
    }
    return NO;
}

- (BOOL)resetAllCredentialsWithError:(NSError **)error {
    os_log_info(_log, "Reset all credentials requested (software-only mode)");
    if (error) {
        *error = [NSError errorWithDomain:YubiKeyOATHErrorDomain
                                    code:YubiKeyOATHErrorNotImplemented
                                userInfo:@{NSLocalizedDescriptionKey: @"Hardware YubiKey OATH not available"}];
    }
    return NO;
}

#pragma mark - Software Fallback

- (nullable NSString *)generateSoftwareTOTPToken:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error {
    TOTPGenerator *generator = [[TOTPGenerator alloc] initWithSecret:secret];
    NSString *token = [generator generateOTP];
    if (token) {
        return token;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:YubiKeyOATHErrorDomain
                                        code:YubiKeyOATHErrorVerificationFailed
                                    userInfo:@{NSLocalizedDescriptionKey: @"Software TOTP generation failed"}];
        }
        return nil;
    }
}

@end

#import "Auth/YubiKeyOATH.h"
#import "Auth/TOTPGenerator.h"
#import "Debug/PDSLogger.h"

NSString * const YubiKeyOATHErrorDomain = @"com.atproto.pds.yubikey.oath";

@interface YubiKeyOATHManager ()

@property (nonatomic, assign, readwrite) YubiKeyConnectionState connectionState;
@property (nonatomic, copy, readwrite, nullable) NSString *connectedKeySerial;

@end

@implementation YubiKeyOATHManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _connectionState = YubiKeyConnectionStateDisconnected;
    }
    return self;
}

- (BOOL)isHardwareAvailable {
    return NO;
}

#pragma mark - Connection Management

- (void)startScanning {
    PDS_LOG_AUTH_INFO(@"YubiKey OATH scanning started (software-only mode)");
    self.connectionState = YubiKeyConnectionStateDisconnected;
}

- (void)stopScanning {
    PDS_LOG_AUTH_INFO(@"YubiKey OATH scanning stopped");
    self.connectionState = YubiKeyConnectionStateDisconnected;
    self.connectedKeySerial = nil;
}

- (void)refreshConnection {
    PDS_LOG_AUTH_INFO(@"YubiKey OATH connection refresh requested (software-only mode)");
    self.connectionState = YubiKeyConnectionStateDisconnected;
    self.connectedKeySerial = nil;
}

#pragma mark - YubiKeyOATH Protocol

- (nullable NSString *)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error {
    PDS_LOG_AUTH_DEBUG(@"Generating TOTP (software fallback)");
    return [self generateSoftwareTOTPToken:secret counter:counter error:error];
}

- (BOOL)setOATHSecret:(NSData *)secret name:(NSString *)name error:(NSError **)error {
    PDS_LOG_AUTH_INFO(@"Set OATH secret requested (software-only mode, name=%@)", name ?: @"");
    if (error) {
        *error = [NSError errorWithDomain:YubiKeyOATHErrorDomain
                                    code:YubiKeyOATHErrorNotImplemented
                                userInfo:@{NSLocalizedDescriptionKey: @"Hardware YubiKey OATH not available. Install YubiKit SDK for hardware support."}];
    }
    return NO;
}

#pragma mark - Credential Management

- (nullable NSArray<NSDictionary *> *)listCredentialsWithError:(NSError **)error {
    PDS_LOG_AUTH_DEBUG(@"List credentials requested (software-only mode)");
    return @[];
}

- (BOOL)deleteCredentialWithName:(NSString *)name error:(NSError **)error {
    PDS_LOG_AUTH_INFO(@"Delete credential requested (software-only mode, name=%@)", name ?: @"");
    if (error) {
        *error = [NSError errorWithDomain:YubiKeyOATHErrorDomain
                                    code:YubiKeyOATHErrorNotImplemented
                                userInfo:@{NSLocalizedDescriptionKey: @"Hardware YubiKey OATH not available"}];
    }
    return NO;
}

- (BOOL)resetAllCredentialsWithError:(NSError **)error {
    PDS_LOG_AUTH_INFO(@"Reset all credentials requested (software-only mode)");
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

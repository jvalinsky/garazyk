#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YubiKeyConnectionState) {
    YubiKeyConnectionStateDisconnected = 0,
    YubiKeyConnectionStateConnecting,
    YubiKeyConnectionStateConnected,
    YubiKeyConnectionStateError
};

extern NSString * const YubiKeyOATHErrorDomain;

typedef NS_ENUM(NSInteger, YubiKeyOATHError) {
    YubiKeyOATHErrorNotImplemented = 1000,
    YubiKeyOATHErrorNoKeyFound,
    YubiKeyOATHErrorConnectionFailed,
    YubiKeyOATHErrorSecretSetFailed,
    YubiKeyOATHErrorInvalidSecret,
    YubiKeyOATHErrorVerificationFailed
};

@protocol YubiKeyOATH <NSObject>
- (nullable NSString *)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error;
- (BOOL)setOATHSecret:(NSData *)secret name:(NSString *)name error:(NSError **)error;
@end

@protocol YubiKeyOATHManagerDelegate <NSObject>
@optional
- (void)yubiKeyManager:(id)manager didChangeConnectionState:(YubiKeyConnectionState)state;
- (void)yubiKeyManager:(id)manager didDetectKeyWithSerial:(NSString *)serial;
- (void)yubiKeyManager:(id)manager didFailWithError:(NSError *)error;
@end

@interface YubiKeyOATHManager : NSObject <YubiKeyOATH>

@property (nonatomic, weak, nullable) id<YubiKeyOATHManagerDelegate> delegate;
@property (nonatomic, assign, readonly) YubiKeyConnectionState connectionState;
@property (nonatomic, copy, readonly, nullable) NSString *connectedKeySerial;
@property (nonatomic, assign, readonly) BOOL isHardwareAvailable;

- (void)startScanning;
- (void)stopScanning;
- (void)refreshConnection;

- (nullable NSArray<NSDictionary *> *)listCredentialsWithError:(NSError **)error;
- (BOOL)deleteCredentialWithName:(NSString *)name error:(NSError **)error;
- (BOOL)resetAllCredentialsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

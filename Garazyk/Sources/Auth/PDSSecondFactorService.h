// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseAccount;
@class PDSServiceDatabases;

extern NSString * const PDSSecondFactorErrorDomain;
extern NSString * const PDSSecondFactorATProtoErrorKey;

typedef NS_ENUM(NSInteger, PDSSecondFactorErrorCode) {
    PDSSecondFactorErrorRequired = 1,
    PDSSecondFactorErrorInvalidToken,
    PDSSecondFactorErrorExpiredToken,
    PDSSecondFactorErrorUnavailable,
};

@interface PDSSecondFactorService : NSObject

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                                  origin:(NSString *)origin;

- (BOOL)accountRequiresSecondFactor:(PDSDatabaseAccount *)account;

- (BOOL)verifyAuthFactorToken:(nullable NSString *)authFactorToken
                    forAccount:(PDSDatabaseAccount *)account
                         error:(NSError **)error;

- (nullable NSDictionary *)beginWebAuthnLoginForAccount:(PDSDatabaseAccount *)account
                                                  error:(NSError **)error;

- (nullable NSString *)completeWebAuthnLoginWithSessionID:(NSString *)sessionID
                                                assertion:(NSDictionary *)assertion
                                                 forAccount:(PDSDatabaseAccount *)account
                                                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

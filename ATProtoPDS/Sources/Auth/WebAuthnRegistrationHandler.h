/*!
 @file WebAuthnRegistrationHandler.h

 @abstract WebAuthn credential registration and authentication handler.

 @discussion Handles WebAuthn registration flow endpoints:
 - POST /auth/webauthn/register/begin - Issue server challenge
 - POST /auth/webauthn/register/complete - Verify attestation, store credential
 - POST /auth/webauthn/assert - Verify assertion, authenticate user

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class PDSDatabase;
@class HttpServer;
@class HttpRequest;
@class HttpResponse;
@class Session;

NS_ASSUME_NONNULL_BEGIN

@interface WebAuthnRegistrationHandler : NSObject

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, copy) NSString *serverOrigin;

- (instancetype)initWithDatabase:(PDSDatabase *)database serverOrigin:(NSString *)serverOrigin;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)registerRoutesWithServer:(HttpServer *)httpServer;

- (void)handleRegisterBegin:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRegisterComplete:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAssert:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
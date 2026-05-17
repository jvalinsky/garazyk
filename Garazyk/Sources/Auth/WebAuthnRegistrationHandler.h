// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

/**
 * @abstract Handles WebAuthn registration and assertion HTTP endpoints.
 */
@interface WebAuthnRegistrationHandler : NSObject

/** Database used to store and load WebAuthn credentials. */
@property (nonatomic, strong) PDSDatabase *database;
/** Origin used when validating WebAuthn client data. */
@property (nonatomic, copy) NSString *serverOrigin;

/** Initializes the handler with credential storage and expected origin. */
- (instancetype)initWithDatabase:(PDSDatabase *)database serverOrigin:(NSString *)serverOrigin;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Registers WebAuthn routes with the supplied HTTP server. */
- (void)registerRoutesWithServer:(HttpServer *)httpServer;

/** Starts credential registration and returns challenge parameters. */
- (void)handleRegisterBegin:(HttpRequest *)request response:(HttpResponse *)response;
/** Completes credential registration from an attestation response. */
- (void)handleRegisterComplete:(HttpRequest *)request response:(HttpResponse *)response;
/** Verifies an assertion response for login or second-factor authentication. */
- (void)handleAssert:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END

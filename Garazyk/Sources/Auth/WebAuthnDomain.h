// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoWebAuthnDomain.h

 @abstract WebAuthn domain models and serialization.

 @discussion Defines WebAuthn data structures for registration and authentication
 ceremonies per W3C WebAuthn specification. Supports FIDO2 passkey authentication.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoWebAuthnRelyingParty

 @abstract Relying party (RP) information for WebAuthn.

 @discussion Identifies the service requesting authentication.
 */
@interface ATProtoWebAuthnRelyingParty : NSObject

/*! Human-readable RP name. */
@property (nonatomic, copy) NSString *name;

/*! RP identifier (typically domain). */
@property (nonatomic, copy) NSString *identifier;

@end

/*!
 @class ATProtoWebAuthnUser

 @abstract User information for WebAuthn registration.

 @discussion User account details for credential creation.
 */
@interface ATProtoWebAuthnUser : NSObject

/*! Unique user identifier (byte handle). */
@property (nonatomic, copy) NSData *identifier;

/*! User account name (e.g., email). */
@property (nonatomic, copy) NSString *name;

/*! Human-readable display name. */
@property (nonatomic, copy) NSString *displayName;

@end

/*!
 @class ATProtoWebAuthnPubKeyCredParam

 @abstract Public key credential parameters.

 @discussion Specifies acceptable credential algorithms.
 */
@interface ATProtoWebAuthnPubKeyCredParam : NSObject

/*! Credential type (always "public-key"). */
@property (nonatomic, copy) NSString *type;

/*! COSE algorithm identifier (-7 for ES256, -8 for EdDSA). */
@property (nonatomic, assign) NSInteger alg;

@end

/*!
 @class ATProtoWebAuthnRegistrationOptions

 @abstract Options for WebAuthn credential registration.

 @discussion Parameters for navigator.credentials.create() call.
 */
@interface ATProtoWebAuthnRegistrationOptions : NSObject

/*! Random challenge bytes (32+ bytes). */
@property (nonatomic, copy) NSData *challenge;

/*! Relying party information. */
@property (nonatomic, strong) ATProtoWebAuthnRelyingParty *rp;

/*! User information. */
@property (nonatomic, strong) ATProtoWebAuthnUser *user;

/*! Acceptable public key algorithms. */
@property (nonatomic, copy) NSArray<ATProtoWebAuthnPubKeyCredParam *> *pubKeyCredParams;

/*! Timeout in milliseconds. */
@property (nonatomic, assign) NSTimeInterval timeout;

/*! Attestation conveyance preference ("none", "direct", "indirect"). */
@property (nonatomic, copy) NSString *attestation;

@end

/*!
 @class ATProtoWebAuthnCredentialDescriptor

 @abstract Descriptor for existing credential.

 @discussion Identifies credential for authentication.
 */
@interface ATProtoWebAuthnCredentialDescriptor : NSObject

/*! Credential type (always "public-key"). */
@property (nonatomic, copy) NSString *type;

/*! Credential identifier. */
@property (nonatomic, copy) NSData *credentialId;

/*! Transport hints (usb, nfc, ble, internal). */
@property (nonatomic, copy) NSArray<NSString *> *transports;

@end

/*!
 @class ATProtoWebAuthnAssertionOptions

 @abstract Options for WebAuthn authentication.

 @discussion Parameters for navigator.credentials.get() call.
 */
@interface ATProtoWebAuthnAssertionOptions : NSObject

/*! Random challenge bytes (32+ bytes). */
@property (nonatomic, copy) NSData *challenge;

/*! Timeout in milliseconds. */
@property (nonatomic, assign) NSTimeInterval timeout;

/*! Relying party identifier (domain). */
@property (nonatomic, copy) NSString *rpId;

/*! Allowed credentials (empty for any). */
@property (nonatomic, copy) NSArray<ATProtoWebAuthnCredentialDescriptor *> *allowCredentials;

/*! User verification requirement ("required", "preferred", "discouraged"). */
@property (nonatomic, copy) NSString *userVerification;

@end

/*!
 @class ATProtoWebAuthnDomain

 @abstract Serialization utilities for WebAuthn options.

 @discussion Converts WebAuthn objects to JSON-compatible dictionaries
 for client transmission.
 */
@interface ATProtoWebAuthnDomain : NSObject

/*! Serialize registration options to dictionary. */
+ (NSDictionary *)dictionaryFromRegistrationOptions:(ATProtoWebAuthnRegistrationOptions *)options;

/*! Serialize assertion options to dictionary. */
+ (NSDictionary *)dictionaryFromAssertionOptions:(ATProtoWebAuthnAssertionOptions *)options;

@end

NS_ASSUME_NONNULL_END

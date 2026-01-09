#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// WebAuthn Data Models

@interface WebAuthnRelyingParty : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *identifier; // id, usually domain
@end

@interface WebAuthnUser : NSObject
@property (nonatomic, copy) NSData *identifier; // id, byte handle
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayName;
@end

@interface WebAuthnPubKeyCredParam : NSObject
@property (nonatomic, copy) NSString *type; // "public-key"
@property (nonatomic, assign) NSInteger alg; // -7 for ES256
@end

@interface WebAuthnRegistrationOptions : NSObject
@property (nonatomic, copy) NSData *challenge;
@property (nonatomic, strong) WebAuthnRelyingParty *rp;
@property (nonatomic, strong) WebAuthnUser *user;
@property (nonatomic, copy) NSArray<WebAuthnPubKeyCredParam *> *pubKeyCredParams;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, copy) NSString *attestation; // "none", "direct", etc
@end

@interface WebAuthnCredentialDescriptor : NSObject
@property (nonatomic, copy) NSString *type; // "public-key"
@property (nonatomic, copy) NSData *credentialId;
@property (nonatomic, copy) NSArray<NSString *> *transports;
@end

@interface WebAuthnAssertionOptions : NSObject
@property (nonatomic, copy) NSData *challenge;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, copy) NSString *rpId;
@property (nonatomic, copy) NSArray<WebAuthnCredentialDescriptor *> *allowCredentials;
@property (nonatomic, copy) NSString *userVerification; // "required", "preferred", "discouraged"
@end

@interface WebAuthnDomain : NSObject
+ (NSDictionary *)dictionaryFromRegistrationOptions:(WebAuthnRegistrationOptions *)options;
+ (NSDictionary *)dictionaryFromAssertionOptions:(WebAuthnAssertionOptions *)options;
@end

NS_ASSUME_NONNULL_END

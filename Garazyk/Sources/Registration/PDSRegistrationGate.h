/*!
 @file PDSRegistrationGate.h

 @abstract Registration gate protocol, composite gate, and factory.

 @discussion
    Defines the pluggable registration gate system for controlling
    account creation on the PDS. Each gate validates a registration
    request and decides whether to allow it through. The composite
    gate combines multiple gates with OR logic: if any gate passes,
    the registration is allowed.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class PDSConfiguration;
@class PDSServiceDatabases;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for registration gate errors. */
extern NSString *const PDSRegistrationGateErrorDomain;

/*!
 @enum PDSRegistrationGateErrorCode

 @abstract Error codes for registration gate validation failures.
 */
typedef NS_ENUM(NSInteger, PDSRegistrationGateErrorCode) {
    PDSRegistrationGateErrorInviteCodeRequired = 1,
    PDSRegistrationGateErrorInvalidInviteCode = 2,
    PDSRegistrationGateErrorPhoneVerificationRequired = 3,
    PDSRegistrationGateErrorInvalidPhoneVerification = 4,
    PDSRegistrationGateErrorCaptchaRequired = 5,
    PDSRegistrationGateErrorInvalidCaptcha = 6,
    PDSRegistrationGateErrorOAuthOnlyRegistration = 7,
    PDSRegistrationGateErrorNoGatePassed = 8,
};

#pragma mark - Protocol

/*!
 @protocol PDSRegistrationGate

 @abstract Validates a registration request before account creation.

 @discussion
    Implementations check whether a createAccount request body
    satisfies a particular registration requirement (invite code,
    phone OTP, CAPTCHA, etc.). The gate is called before the
    account is created; if it returns NO, the registration is
    rejected with the provided error.
 */
@protocol PDSRegistrationGate <NSObject>

/*! Gate identifier for config, logging, and describeServer (e.g. "invite_code"). */
@property (nonatomic, readonly) NSString *gateIdentifier;

/*!
 @method validateRegistrationRequest:configuration:error:
 @abstract Check whether the registration request is allowed through this gate.
 @param body The JSON body of the createAccount request.
 @param configuration The PDS configuration.
 @param error On failure, set to a gate-specific error.
 @return YES if the request passes this gate, NO otherwise.
 */
- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error;

@end

#pragma mark - Composite Gate

/*!
 @class PDSCompositeRegistrationGate

 @abstract Combines multiple registration gates with OR logic.

 @discussion
    If ANY gate in the composite passes, the registration is allowed.
    This enables configurations like "invite code OR phone OTP".
    If no gates are added, the composite always passes (open registration).
 */
@interface PDSCompositeRegistrationGate : NSObject <PDSRegistrationGate>

/*! Add a gate to the composite. */
- (void)addGate:(id<PDSRegistrationGate>)gate;

/*! The individual gates in this composite. */
@property (nonatomic, readonly) NSArray<id<PDSRegistrationGate>> *gates;

/*! Whether the composite contains a gate with the given identifier. */
- (BOOL)containsGateWithIdentifier:(NSString *)identifier;

@end

#pragma mark - Open Gate

/*!
 @class PDSOpenRegistrationGate

 @abstract A gate that always passes (open registration, no restrictions).
 */
@interface PDSOpenRegistrationGate : NSObject <PDSRegistrationGate>
@end

#pragma mark - Factory

/*!
 @class PDSRegistrationGateFactory

 @abstract Assembles a registration gate from PDS configuration.

 @discussion
    Reads the PDS configuration and creates a composite gate
    containing all enabled gates. Supports custom gate registration
    via registerGateClass:forIdentifier:.
 */
@interface PDSRegistrationGateFactory : NSObject

/*!
 @method gateFromConfiguration:serviceDatabases:error:
 @abstract Create a registration gate from the PDS configuration.
 @param configuration The PDS configuration.
 @param serviceDatabases The service databases (for invite code validation).
 @param error On failure, set to a configuration error.
 @return A registration gate (composite if multiple gates enabled, single otherwise).
 */
+ (nullable id<PDSRegistrationGate>)gateFromConfiguration:(PDSConfiguration *)configuration
                                         serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                                    error:(NSError **)error;

/*!
 @method registerGateClass:forIdentifier:
 @abstract Register a custom gate class for lookup by identifier.
 @param gateClass Class implementing PDSRegistrationGate.
 @param identifier Gate identifier (e.g. "my_custom_gate").
 */
+ (void)registerGateClass:(Class)gateClass forIdentifier:(NSString *)identifier;

/*!
 @method unregisterGateForIdentifier:
 @abstract Remove a previously registered custom gate.
 */
+ (void)unregisterGateForIdentifier:(NSString *)identifier;

/*! Clear all registered custom gates. */
+ (void)resetCustomGates;

@end

NS_ASSUME_NONNULL_END

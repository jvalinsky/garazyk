// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRegistrationGate.m

 @abstract Registration gate composite and factory implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSRegistrationGate.h"
#import "Registration/PDSInviteCodeRegistrationGate.h"
#import "Registration/PDSPhoneOTPRegistrationGate.h"
#import "Registration/PDSCaptchaRegistrationGate.h"
#import "Registration/PDSOAuthOnlyRegistrationGate.h"
#import "App/PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "Email/PDSEnvironmentSecretsProvider.h"
#import "Debug/PDSLogger.h"

NSString *const PDSRegistrationGateErrorDomain = @"com.atproto.pds.registrationgate";

#pragma mark - PDSCompositeRegistrationGate

@interface PDSCompositeRegistrationGate ()
@property (nonatomic, strong) NSMutableArray<id<PDSRegistrationGate>> *mutableGates;
@end

@implementation PDSCompositeRegistrationGate

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableGates = [NSMutableArray array];
    }
    return self;
}

- (NSString *)gateIdentifier {
    return @"composite";
}

- (NSArray<id<PDSRegistrationGate>> *)gates {
    return [self.mutableGates copy];
}

- (void)addGate:(id<PDSRegistrationGate>)gate {
    if (gate) {
        [self.mutableGates addObject:gate];
    }
}

- (BOOL)containsGateWithIdentifier:(NSString *)identifier {
    for (id<PDSRegistrationGate> gate in self.mutableGates) {
        if ([gate.gateIdentifier isEqualToString:identifier]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    // No gates = open registration
    if (self.mutableGates.count == 0) {
        return YES;
    }

    // OR logic: if ANY gate passes, the registration is allowed
    NSError *lastError = nil;
    for (id<PDSRegistrationGate> gate in self.mutableGates) {
        NSError *gateError = nil;
        if ([gate validateRegistrationRequest:body
                                configuration:configuration
                                        error:&gateError]) {
            return YES;
        }
        lastError = gateError;
    }

    // All gates failed
    if (error) {
        *error = lastError ?: [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                                   code:PDSRegistrationGateErrorNoGatePassed
                                               userInfo:@{
                                                   NSLocalizedDescriptionKey:
                                                       @"Registration rejected: no gate passed"
                                               }];
    }
    return NO;
}

@end

#pragma mark - PDSOpenRegistrationGate

@implementation PDSOpenRegistrationGate

- (NSString *)gateIdentifier {
    return @"open";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    return YES;
}

@end

#pragma mark - PDSRegistrationGateFactory

static NSMutableDictionary<NSString *, Class> *sCustomGateClasses = nil;

@implementation PDSRegistrationGateFactory

+ (void)initialize {
    if (self == [PDSRegistrationGateFactory class]) {
        sCustomGateClasses = [NSMutableDictionary dictionary];
    }
}

+ (nullable id<PDSRegistrationGate>)gateFromConfiguration:(PDSConfiguration *)configuration
                                         serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                                    error:(NSError **)error {
    PDSCompositeRegistrationGate *composite = [[PDSCompositeRegistrationGate alloc] init];

    // Invite code gate
    if (configuration.inviteCodeRequired) {
        PDSInviteCodeRegistrationGate *inviteGate =
            [[PDSInviteCodeRegistrationGate alloc] initWithServiceDatabases:serviceDatabases];
        [composite addGate:inviteGate];
    }

    // Phone OTP gate
    if (configuration.phoneVerificationRequired) {
        NSString *providerName = configuration.phoneVerificationProvider ?: @"none";
        id<PDSPhoneVerificationProvider> phoneProvider = nil;

        if (![providerName isEqualToString:@"none"] && ![providerName isEqualToString:@"mock"]) {
            PDSEnvironmentSecretsProvider *secretsProvider = [[PDSEnvironmentSecretsProvider alloc] init];
            NSError *providerError = nil;
            phoneProvider = [PDSPhoneVerificationProviderFactory providerWithName:providerName
                                                                   configuration:@{}
                                                                  secretsProvider:secretsProvider
                                                                            error:&providerError];
            if (!phoneProvider) {
                PDS_LOG_WARN(@"[RegistrationGate] Failed to create phone verification provider '%@': %@",
                             providerName, providerError.localizedDescription);
            }
        } else if ([providerName isEqualToString:@"mock"]) {
            NSError *providerError = nil;
            phoneProvider = [PDSPhoneVerificationProviderFactory providerWithName:providerName
                                                                           error:&providerError];
        }

        PDSPhoneOTPRegistrationGate *phoneGate =
            [[PDSPhoneOTPRegistrationGate alloc] initWithPhoneVerificationProvider:phoneProvider];
        [composite addGate:phoneGate];
    }

    // CAPTCHA gate
    if (configuration.captchaRequired) {
        PDSCaptchaRegistrationGate *captchaGate =
            [[PDSCaptchaRegistrationGate alloc] initWithProvider:configuration.captchaProvider
                                                        siteKey:configuration.captchaSiteKey
                                                      secretKey:configuration.captchaSecretKey];
        [composite addGate:captchaGate];
    }

    // OAuth-only gate
    if (configuration.oauthOnlyRegistration) {
        PDSOAuthOnlyRegistrationGate *oauthGate =
            [[PDSOAuthOnlyRegistrationGate alloc] init];
        [composite addGate:oauthGate];
    }

    // Custom gates from registry
    for (NSString *identifier in sCustomGateClasses) {
        Class gateClass = sCustomGateClasses[identifier];
        if ([configuration isRegistrationGateEnabled:identifier]) {
            id<PDSRegistrationGate> gate = [[gateClass alloc] init];
            if (gate) {
                [composite addGate:gate];
            }
        }
    }

    // If no gates were added, return an open gate
    if (composite.gates.count == 0) {
        return [[PDSOpenRegistrationGate alloc] init];
    }

    // If only one gate, return it directly (no composite overhead)
    if (composite.gates.count == 1) {
        return composite.gates.firstObject;
    }

    return composite;
}

+ (void)registerGateClass:(Class)gateClass forIdentifier:(NSString *)identifier {
    @synchronized(sCustomGateClasses) {
        sCustomGateClasses[identifier] = gateClass;
    }
}

+ (void)unregisterGateForIdentifier:(NSString *)identifier {
    @synchronized(sCustomGateClasses) {
        [sCustomGateClasses removeObjectForKey:identifier];
    }
}

+ (void)resetCustomGates {
    @synchronized(sCustomGateClasses) {
        [sCustomGateClasses removeAllObjects];
    }
}

@end

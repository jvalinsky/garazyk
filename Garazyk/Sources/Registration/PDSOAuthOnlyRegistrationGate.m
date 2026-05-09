/*!
 @file PDSOAuthOnlyRegistrationGate.m

 @abstract OAuth-only registration gate implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSOAuthOnlyRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "App/PDSConfiguration.h"

@implementation PDSOAuthOnlyRegistrationGate

- (NSString *)gateIdentifier {
    return @"oauth_only";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    // This gate always rejects direct API signups.
    // Registration must go through the OAuth2 flow instead.
    if (error) {
        *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                     code:PDSRegistrationGateErrorOAuthOnlyRegistration
                                 userInfo:@{
                                     NSLocalizedDescriptionKey:
                                         @"Direct account creation is not allowed. "
                                         @"Please register through the OAuth2 flow."
                                 }];
    }
    return NO;
}

@end

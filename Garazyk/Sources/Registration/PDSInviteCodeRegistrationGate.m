/*!
 @file PDSInviteCodeRegistrationGate.m

 @abstract Invite code registration gate implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Registration/PDSInviteCodeRegistrationGate.h"
#import "Registration/PDSRegistrationGate.h"
#import "Database/Service/ServiceDatabases.h"
#import "App/PDSConfiguration.h"

@implementation PDSInviteCodeRegistrationGate

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
    }
    return self;
}

- (NSString *)gateIdentifier {
    return @"invite_code";
}

- (BOOL)validateRegistrationRequest:(NSDictionary *)body
                       configuration:(PDSConfiguration *)configuration
                               error:(NSError **)error {
    NSString *inviteCode = body[@"inviteCode"];
    if (!inviteCode || inviteCode.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInviteCodeRequired
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Invite code required"
                                     }];
        }
        return NO;
    }

    NSError *inviteError = nil;
    if (![self.serviceDatabases useInviteCode:inviteCode error:&inviteError]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSRegistrationGateErrorDomain
                                         code:PDSRegistrationGateErrorInvalidInviteCode
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             inviteError.localizedDescription
                                                 ?: @"Invalid or expired invite code"
                                     }];
        }
        return NO;
    }

    return YES;
}

@end

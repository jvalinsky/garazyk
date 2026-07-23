// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcServerPack+Describe.h"
#import "Network/XrpcServerPack_Internal.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcServiceAuthHelper.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Services/PDS/PDSAccountService.h"
#import "Services/PDS/PDSRepositoryService.h"
#import "Admin/PDSAdminController.h"
#import "Auth/PDSSecondFactorService.h"
#import "Auth/Secp256k1.h"
#import "Core/ATProtoValidator.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Core/DID.h"
#import "Core/PDSAccountEvents.h"
#import "Debug/GZLogger.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcServerPack (Describe)

+ (void)registerDescribeServerWithDispatcher:(XrpcDispatcher *)dispatcher
                               configuration:(ATProtoServiceConfiguration *)config
                            registrationGate:(nullable id<PDSRegistrationGate>)registrationGate {
#pragma mark - com.atproto.server.describeServer
    [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_describeServer handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *issuer = [config canonicalIssuerWithPortHint:0];
        NSString *hostname = [config canonicalHostname];
        NSString *serverDid = XrpcDidWebIdentifierFromIssuer(issuer, hostname);
        NSArray *availableUserDomains = config.availableUserDomains ?: (hostname.length > 0 ? @[hostname] : @[]);

        // Determine gate flags from the registration gate
        BOOL inviteCodeRequired = config.inviteCodeRequired;
        BOOL phoneVerificationRequired = config.phoneVerificationRequired;
        if ([registrationGate respondsToSelector:@selector(containsGateWithIdentifier:)]) {
            inviteCodeRequired = [(id)registrationGate containsGateWithIdentifier:@"invite_code"];
            phoneVerificationRequired = [(id)registrationGate containsGateWithIdentifier:@"phone_otp"];
        }

        NSDictionary *result = @{
            @"inviteCodeRequired": @(inviteCodeRequired),
            @"phoneVerificationRequired": @(phoneVerificationRequired),
            @"availableUserDomains": availableUserDomains,
            @"links": @{
                @"privacyPolicy": config.privacyPolicyURL ?: @"",
                @"termsOfService": config.termsOfServiceURL ?: @""
            },
            @"did": serverDid,
            @"version": @"0.1.0"
        };

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
}

@end

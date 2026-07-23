// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcServerPack+Health.h"
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

@implementation XrpcServerPack (Health)

+ (void)registerHealthEndpointWithDispatcher:(XrpcDispatcher *)dispatcher {
    [dispatcher registerMethod:@"_health" handler:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
        NSString *status = health[@"status"];
        
        // Return 503 if critical, 200 otherwise (including warnings)
        if ([status isEqualToString:@"critical"]) {
            response.statusCode = HttpStatusServiceUnavailable;
        } else {
            response.statusCode = HttpStatusOK;
        }
        
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:health];
        result[@"version"] = @"0.1.0";
        result[@"status"] = status ?: @"healthy";
        
        [response setJsonBody:result];
    }];
}

@end

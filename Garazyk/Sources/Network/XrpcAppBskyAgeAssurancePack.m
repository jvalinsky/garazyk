/*!
 @file XrpcAppBskyAgeAssurancePack.m

 @abstract XRPC route pack for app.bsky.ageassurance endpoints.
 */

#import "Network/XrpcAppBskyAgeAssurancePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"

@implementation XrpcAppBskyAgeAssurancePack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {
    // app.bsky.ageassurance.begin - Initiate age assurance
    [dispatcher registerMethod:@"app.bsky.ageassurance.begin"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *email = body[@"email"];
        NSString *language = body[@"language"];
        NSString *countryCode = body[@"countryCode"];

        if (!email || !language || !countryCode) {
            [XrpcErrorHelper setValidationError:response message:@"email, language, and countryCode are required"];
            return;
        }

        // Create age assurance state
        NSString *stateId = [[NSUUID UUID] UUIDString];
        NSString *token = [[NSUUID UUID] UUIDString];

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"id": stateId,
            @"status": @"pending",
            @"token": token
        }];
    }];

    // app.bsky.ageassurance.getConfig - Get age assurance configuration
    [dispatcher registerMethod:@"app.bsky.ageassurance.getConfig"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        // Return age assurance configuration
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"enabled": @YES,
            @"methods": @[
                @{@"type": @"email", @"description": @"Verify age via email"},
                @{@"type": @"id", @"description": @"Verify age with ID document"}
            ],
            @"minimumAge": @18,
            @"supportedCountries": @[@"US", @"CA", @"GB", @"AU", @"NZ"]
        }];
    }];

    // app.bsky.ageassurance.getState - Get age assurance state
    [dispatcher registerMethod:@"app.bsky.ageassurance.getState"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSString *countryCode = [request queryParamForKey:@"countryCode"];
        NSString *regionCode = [request queryParamForKey:@"regionCode"];

        if (!countryCode) {
            [XrpcErrorHelper setValidationError:response message:@"countryCode is required"];
            return;
        }

        // Return state (would check DB for actual state)
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"state": @{
                @"id": @"",
                @"status": @"none"
            },
            @"metadata": @{
                @"countryCode": countryCode,
                @"regionCode": regionCode ?: @"",
                @"computedAt": [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]]
            }
        }];
    }];
}

@end

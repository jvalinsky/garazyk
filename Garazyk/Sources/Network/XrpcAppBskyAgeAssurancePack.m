/*!
 @file XrpcAppBskyAgeAssurancePack.m

 @abstract XRPC route pack for app.bsky.ageassurance endpoints.
 */

#import "Network/XrpcAppBskyAgeAssurancePack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "AppView/Services/AgeAssuranceService.h"

@implementation XrpcAppBskyAgeAssurancePack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
           ageAssuranceService:(nullable AgeAssuranceService *)ageAssuranceService {
    // app.bsky.ageassurance.begin - Initiate age assurance
    [dispatcher registerMethod:@"app.bsky.ageassurance.begin"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        // Extract DID from auth header (simplified: assume it's the DID)
        NSString *token = [authHeader hasPrefix:@"Bearer "] ? [authHeader substringFromIndex:7] : authHeader;
        NSString *did = token; 

        NSDictionary *body = request.jsonBody;
        NSString *email = body[@"email"];
        NSString *language = body[@"language"];
        NSString *countryCode = body[@"countryCode"];
        NSString *regionCode = body[@"regionCode"];

        if (!email || !language || !countryCode) {
            [XrpcErrorHelper setValidationError:response message:@"email, language, and countryCode are required"];
            return;
        }

        if (ageAssuranceService) {
            NSError *error = nil;
            NSDictionary *result = [ageAssuranceService beginAgeAssurance:did
                                                                    email:email
                                                                 language:language
                                                              countryCode:countryCode
                                                               regionCode:regionCode
                                                                    error:&error];
            if (error) {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                return;
            }
            response.statusCode = HttpStatusOK;
            [response setJsonBody:result];
        } else {
            // Create age assurance state (Mock)
            NSString *stateId = [[NSUUID UUID] UUIDString];
            NSString *token = [[NSUUID UUID] UUIDString];

            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{
                @"id": stateId,
                @"status": @"pending",
                @"token": token
            }];
        }
    }];

    // app.bsky.ageassurance.getConfig - Get age assurance configuration
    [dispatcher registerMethod:@"app.bsky.ageassurance.getConfig"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        if (ageAssuranceService) {
            NSError *error = nil;
            NSDictionary *config = [ageAssuranceService getAgeAssuranceConfig:&error];
            if (error) {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                return;
            }
            response.statusCode = HttpStatusOK;
            [response setJsonBody:config];
        } else {
            // Return default configuration
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
        }
    }];

    // app.bsky.ageassurance.getState - Get age assurance state
    [dispatcher registerMethod:@"app.bsky.ageassurance.getState"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        // Extract DID
        NSString *token = [authHeader hasPrefix:@"Bearer "] ? [authHeader substringFromIndex:7] : authHeader;
        NSString *did = token;

        NSString *countryCode = [request queryParamForKey:@"countryCode"];
        NSString *regionCode = [request queryParamForKey:@"regionCode"];

        if (!countryCode) {
            [XrpcErrorHelper setValidationError:response message:@"countryCode is required"];
            return;
        }

        if (ageAssuranceService) {
            NSError *error = nil;
            NSDictionary *state = [ageAssuranceService getAgeAssuranceState:did
                                                               countryCode:countryCode
                                                                regionCode:regionCode
                                                                     error:&error];
            if (error) {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                return;
            }
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{
                @"state": state ?: @{ @"id": @"", @"status": @"none" },
                @"metadata": @{
                    @"countryCode": countryCode,
                    @"regionCode": regionCode ?: @"",
                    @"computedAt": [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]]
                }
            }];
        } else {
            // Return mock state
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
        }
    }];
}

@end

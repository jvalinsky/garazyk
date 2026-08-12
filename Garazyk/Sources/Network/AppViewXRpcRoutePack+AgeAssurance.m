// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/AgeAssuranceService.h"
#import "Auth/AuthClaimTypeCheck.h"

@implementation ATProtoAppViewXRpcRoutePack (AgeAssurance)

- (void)handleAgeAssuranceBegin:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    BOOL typeMismatch = NO;
    NSString *email = AuthTypedValue(body, @"email", [NSString class], &typeMismatch);
    NSString *language = AuthTypedValue(body, @"language", [NSString class], &typeMismatch);
    NSString *countryCode = AuthTypedValue(body, @"countryCode", [NSString class], &typeMismatch);
    NSString *regionCode = AuthTypedValue(body, @"regionCode", [NSString class], &typeMismatch);
    if (typeMismatch) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"Request field has wrong type" }];
        return;
    }
    if (!body || !email || !language || !countryCode) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"email, language, and countryCode required" }];
        return;
    }

    if (!self.ageAssuranceService) {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Age assurance service not available" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [self.ageAssuranceService beginAgeAssurance:actorDID
                                                                email:email
                                                             language:language
                                                          countryCode:countryCode
                                                           regionCode:regionCode
                                                                error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result];
}

- (void)handleAgeAssuranceGetConfig:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response
{
    if (!self.ageAssuranceService) {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Age assurance service not available" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *config = [self.ageAssuranceService getAgeAssuranceConfig:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription }]; return; }
    response.statusCode = 200;
    [response setJsonBody:config];
}

- (void)handleAgeAssuranceGetState:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSString *countryCode = [request queryParamForKey:@"countryCode"];
    if (!countryCode) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"countryCode parameter is required" }];
        return;
    }

    if (!self.ageAssuranceService) {
        response.statusCode = 503;
        [response setJsonBody:@{ @"error": @"ServiceUnavailable", @"message": @"Age assurance service not available" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *state = [self.ageAssuranceService getAgeAssuranceState:actorDID
                                                            countryCode:countryCode
                                                             regionCode:[request queryParamForKey:@"regionCode"]
                                                                  error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription }]; return; }
    
    response.statusCode = 200;
    [response setJsonBody:@{
        @"state": state ?: @{ @"id": @"", @"status": @"none" },
        @"metadata": @{
            @"countryCode": countryCode,
            @"regionCode": [request queryParamForKey:@"regionCode"] ?: @"",
            @"computedAt": [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]]
        }
    }];
}

@end
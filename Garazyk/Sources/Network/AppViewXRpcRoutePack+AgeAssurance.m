// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/AgeAssuranceService.h"

@implementation AppViewXRpcRoutePack (AgeAssurance)

- (void)handleAgeAssuranceBegin:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    if (!body || !body[@"email"] || !body[@"language"] || !body[@"countryCode"]) {
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
                                                                email:body[@"email"]
                                                             language:body[@"language"]
                                                          countryCode:body[@"countryCode"]
                                                           regionCode:body[@"regionCode"]
                                                                error:&error];
    if (error) { response.statusCode = 500; [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription }]; return; }
    response.statusCode = 200;
    [response setJsonBody:result];
}

- (void)handleAgeAssuranceGetConfig:(HttpRequest *)request response:(HttpResponse *)response
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

- (void)handleAgeAssuranceGetState:(HttpRequest *)request response:(HttpResponse *)response
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
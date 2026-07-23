// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack_Internal.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "AppView/Services/ContactService.h"

@implementation AppViewXRpcRoutePack (Contact)

- (void)handleStartPhoneVerification:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSString *phone = body[@"phoneNumber"];
    if (!phone) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"phoneNumber is required" }];
        return;
    }

    NSError *error = nil;
    NSString *vId = [self.contactService startPhoneVerification:phone actor:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"id": vId ?: @"" }];
}

- (void)handleVerifyPhone:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSString *phone = body[@"phoneNumber"];
    NSString *code = body[@"code"];
    if (!phone || !code) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"phoneNumber and code are required" }];
        return;
    }

    NSError *error = nil;
    NSString *token = [self.contactService verifyPhone:phone code:code actor:actorDID error:&error];
    if (error) {
        response.statusCode = 401;
        [response setJsonBody:@{ @"error": @"AuthenticationFailed", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"token": token ?: @"" }];
}

- (void)handleImportContacts:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSArray *contacts = body[@"contacts"];
    NSString *token = body[@"token"];
    if (!contacts || !token) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"contacts and token are required" }];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [self.contactService importContacts:contacts token:token actor:actorDID error:&error];
    if (error) {
        response.statusCode = error.code == 401 ? 401 : 500;
        [response setJsonBody:@{ @"error": error.code == 401 ? @"AuthenticationFailed" : @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:result ?: @{}];
}

- (void)handleGetContactMatches:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSArray *matches = [self.contactService getMatchesForActor:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{ @"matches": matches ?: @[] }];
}

- (void)handleDismissContactMatch:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSDictionary *body = request.jsonBody;
    NSString *matchDID = body[@"did"];
    if (!matchDID) {
        response.statusCode = 400;
        [response setJsonBody:@{ @"error": @"InvalidRequest", @"message": @"did is required" }];
        return;
    }

    NSError *error = nil;
    BOOL ok = [self.contactService dismissMatch:matchDID actor:actorDID error:&error];
    if (!ok) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleGetContactSyncStatus:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    NSDictionary *status = [self.contactService getSyncStatusForActor:actorDID error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:status ?: @{}];
}

- (void)handleRemoveContactData:(HttpRequest *)request response:(HttpResponse *)response
{
    NSString *actorDID = [self requireAuth:request response:response];
    if (!actorDID) return;

    NSError *error = nil;
    BOOL ok = [self.contactService removeDataForActor:actorDID error:&error];
    if (!ok) {
        response.statusCode = 500;
        [response setJsonBody:@{ @"error": @"InternalServerError", @"message": error.localizedDescription ?: @"Failed" }];
        return;
    }
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

@end
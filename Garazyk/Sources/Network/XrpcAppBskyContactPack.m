/*!
 @file XrpcAppBskyContactPack.m

 @abstract XRPC route pack for app.bsky.contact endpoints.
 */

#import "Network/XrpcAppBskyContactPack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "AppView/Services/ContactService.h"

@implementation XrpcAppBskyContactPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 contactService:(ContactService *)contactService
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {

    // app.bsky.contact.startPhoneVerification
    [dispatcher registerMethod:@"app.bsky.contact.startPhoneVerification"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *phoneNumber = body[@"phoneNumber"];
        if (!phoneNumber || phoneNumber.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"phoneNumber is required"];
            return;
        }

        NSError *error = nil;
        NSString *verificationId = [contactService startPhoneVerification:phoneNumber
                                                                    actor:actorDID
                                                                    error:&error];
        if (error || !verificationId) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to start verification"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"verificationId": verificationId}];
    }];

    // app.bsky.contact.verifyPhone
    [dispatcher registerMethod:@"app.bsky.contact.verifyPhone"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *phoneNumber = body[@"phoneNumber"];
        NSString *code = body[@"code"];
        if (!phoneNumber || !code) {
            [XrpcErrorHelper setValidationError:response message:@"phoneNumber and code are required"];
            return;
        }

        NSError *error = nil;
        NSString *token = [contactService verifyPhone:phoneNumber code:code actor:actorDID error:&error];
        if (error || !token) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"InvalidCode", @"message": error.localizedDescription ?: @"Invalid verification code"}];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"token": token}];
    }];

    // app.bsky.contact.importContacts
    [dispatcher registerMethod:@"app.bsky.contact.importContacts"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *token = body[@"token"];
        NSArray *contacts = body[@"contacts"];
        if (!token || !contacts) {
            [XrpcErrorHelper setValidationError:response message:@"token and contacts are required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [contactService importContacts:contacts
                                                        token:token
                                                        actor:actorDID
                                                        error:&error];
        if (error || !result) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to import contacts"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:result];
    }];

    // app.bsky.contact.getMatches
    [dispatcher registerMethod:@"app.bsky.contact.getMatches"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSError *error = nil;
        NSArray *matches = [contactService getMatchesForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"matches": matches ?: @[]}];
    }];

    // app.bsky.contact.dismissMatch
    [dispatcher registerMethod:@"app.bsky.contact.dismissMatch"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *matchDID = body[@"did"];
        if (!matchDID) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [contactService dismissMatch:matchDID actor:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // app.bsky.contact.getSyncStatus
    [dispatcher registerMethod:@"app.bsky.contact.getSyncStatus"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSError *error = nil;
        NSDictionary *status = [contactService getSyncStatusForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:status ?: @{@"syncedAt": @"", @"matchesCount": @(0)}];
    }];

    // app.bsky.contact.removeData
    [dispatcher registerMethod:@"app.bsky.contact.removeData"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSError *error = nil;
        BOOL success = [contactService removeDataForActor:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // app.bsky.contact.sendNotification (admin/system only)
    [dispatcher registerMethod:@"app.bsky.contact.sendNotification"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        // This should require admin/system role auth
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter adminController:adminController request:request response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *fromDID = body[@"from"];
        NSString *toDID = body[@"to"];
        if (!fromDID || !toDID) {
            [XrpcErrorHelper setValidationError:response message:@"from and to are required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [contactService sendNotificationFrom:fromDID to:toDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];
}

@end

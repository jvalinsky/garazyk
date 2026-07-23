// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+Security.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (Security)

- (NSDictionary *)fetchActiveSessionsForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:[self pathWithSegments:@[@"admin", @"api", @"accounts", did, @"sessions"]]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"sessions_failed", @"message": error.localizedDescription ?: @"Failed to fetch sessions"};
    }
    return response ?: @{};
}

- (NSDictionary *)revokeSessionForDID:(NSString *)did sessionID:(NSString *)sessionID {
    if (did.length == 0 || sessionID.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and session ID required"};
    }
    NSURL *url = [self URLByAppendingPath:[self pathWithSegments:@[@"admin", @"api", @"accounts", did, @"sessions", @"revoke"]]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"id": sessionID};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"revoke_session_failed", @"message": error.localizedDescription ?: @"Failed to revoke session"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchAppPasswordsForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:[self pathWithSegments:@[@"admin", @"api", @"accounts", did, @"app-passwords"]]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"app_passwords_failed", @"message": error.localizedDescription ?: @"Failed to fetch app passwords"};
    }
    return response ?: @{};
}

- (NSDictionary *)createAppPasswordForDID:(NSString *)did name:(NSString *)passwordName {
    if (did.length == 0 || passwordName.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and name required"};
    }
    NSURL *url = [self URLByAppendingPath:[self pathWithSegments:@[@"admin", @"api", @"accounts", did, @"app-passwords"]]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"name": passwordName};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"create_app_password_failed", @"message": error.localizedDescription ?: @"Failed to create app password"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteAppPasswordForDID:(NSString *)did passwordName:(NSString *)passwordName {
    if (did.length == 0 || passwordName.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and name required"};
    }
    NSURL *url = [self URLByAppendingPath:[self pathWithSegments:@[@"admin", @"api", @"accounts", did, @"app-passwords", @"revoke"]]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"name": passwordName};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"delete_app_password_failed", @"message": error.localizedDescription ?: @"Failed to delete app password"};
    }
    return response ?: @{};
}

@end

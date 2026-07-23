// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#pragma once

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Auth/JWT.h"

BOOL validateDidWebServiceAuthForAccountCreation(HttpRequest * _Nonnull request,
                                                        HttpResponse * _Nonnull response,
                                                        NSString *did,
                                                        ATProtoServiceConfiguration *config);
BOOL createInviteCodeInDatabase(PDSServiceDatabases *serviceDatabases,
                                       NSString *accountDid,
                                       NSInteger maxUses,
                                       NSString **outCode,
                                       NSError **error);
BOOL isLikelyEmail(NSString *email);
BOOL updateAccountEmail(PDSServiceDatabases *serviceDatabases,
                               NSString *did,
                               NSString *email,
                               NSError **error);
BOOL updateAccountHandle(PDSServiceDatabases *serviceDatabases,
                                NSString *did,
                                NSString *handle,
                                NSError **error);
NSData *pbkdf2HashPassword(NSString *password, NSData *salt, NSError **error);
NSDictionary *payloadDictionaryFromJWT(JWT *jwt, NSError **error);

@interface JWT (Base64URL)
+ (nullable NSData *)base64URLDecode:(NSString *)string error:(NSError * _Nullable * _Nullable)error;
@end

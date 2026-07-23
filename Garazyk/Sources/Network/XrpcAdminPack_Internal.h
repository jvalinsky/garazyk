// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#pragma once

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Admin/PDSAdminController.h"
#import "Auth/JWT.h"

@class PDSDatabaseAccount;
@class PDSRecordService;
@class PDSRepositoryService;

// Forward declarations for shared helper functions (used by category files)
BOOL parseStrictIntegerString(NSString *str, NSInteger *outValue);
NSDictionary *adminAccountViewFromAccount(PDSDatabaseAccount *account);
NSArray<NSString *> *queryArrayValues(HttpRequest *request, NSString *key);
NSArray<NSDictionary *> *loadAdminInviteCodeViews(PDSServiceDatabases *serviceDatabases,
                                                   NSString *sort, NSInteger limit,
                                                   NSInteger offset, NSError **error);
BOOL setInviteEnabledForAccount(PDSServiceDatabases *serviceDatabases, NSString *did,
                                BOOL enabled, NSError **error);
BOOL deleteAccountAsAdmin(PDSServiceDatabases *serviceDatabases, NSString *did, NSError **error);
BOOL updateAccountPassword(PDSServiceDatabases *serviceDatabases, NSString *did,
                           NSString *password, NSError **error);
BOOL updateAccountSigningKey(PDSServiceDatabases *serviceDatabases, NSString *did,
                             NSString *signingKey, NSError **error);
NSDictionary *subjectStatusSubjectFromRequestBody(NSDictionary *body);
BOOL resolveAccountIdentifierToDid(PDSServiceDatabases *serviceDatabases, NSString *identifier,
                                   NSString **outDid, NSError **error);
NSArray<NSString *> *validatedUniqueStringArrayFromJSONValue(id value, NSString *fieldName, NSError **error);

/// isLikelyEmail, updateAccountEmail, and pbkdf2HashPassword are provided by XrpcServerPack_Internal.h

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "PDSCLIDefinitions.h"
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSCLIAccountManager : NSObject

+ (NSArray<PDSDatabaseAccount *> *)listAccountsWithContext:(PDSCLICommandContext *)context
                                                    filter:(NSString *)filter
                                                    limit:(NSInteger)limit;

+ (nullable PDSDatabaseAccount *)getAccountWithContext:(PDSCLICommandContext *)context
                                               identifier:(NSString *)identifier;

+ (BOOL)createAccountWithContext:(PDSCLICommandContext *)context
                              email:(NSString *)email
                            handle:(NSString *)handle
                          password:(NSString *)password;

+ (BOOL)deactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)reactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
+ (BOOL)deleteAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;

+ (BOOL)updateEmailWithContext:(PDSCLICommandContext *)context
                             did:(NSString *)did
                           email:(NSString *)email;

+ (BOOL)updateHandleWithContext:(PDSCLICommandContext *)context
                              did:(NSString *)did
                           handle:(NSString *)handle;

+ (BOOL)updatePlcEndpointWithContext:(PDSCLICommandContext *)context
                                  did:(NSString *)did
                          newEndpoint:(NSString *)newEndpoint;

+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context;
+ (NSString *)pdsHostnameForContext:(PDSCLICommandContext *)context;
+ (NSString *)pdsServiceEndpointForContext:(PDSCLICommandContext *)context;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "PDSCLIDefinitions.h"
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Account-management operations used by the PDS command-line interface.
 */
@interface PDSCLIAccountManager : NSObject

/** Lists accounts matching an optional filter and limit. */
+ (NSArray<PDSDatabaseAccount *> *)listAccountsWithContext:(PDSCLICommandContext *)context
                                                    filter:(NSString *)filter
                                                    limit:(NSInteger)limit;

/** Returns the account matching a DID, handle, or other accepted identifier. */
+ (nullable PDSDatabaseAccount *)getAccountWithContext:(PDSCLICommandContext *)context
                                               identifier:(NSString *)identifier;

/** Creates an account from CLI-supplied identity and password fields. */
+ (BOOL)createAccountWithContext:(PDSCLICommandContext *)context
                              email:(NSString *)email
                            handle:(NSString *)handle
                          password:(NSString *)password;

/** Deactivates an account by DID. */
+ (BOOL)deactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
/** Reactivates a previously deactivated account by DID. */
+ (BOOL)reactivateAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;
/** Deletes an account by DID. */
+ (BOOL)deleteAccountWithContext:(PDSCLICommandContext *)context did:(NSString *)did;

/** Updates an account email address by DID. */
+ (BOOL)updateEmailWithContext:(PDSCLICommandContext *)context
                             did:(NSString *)did
                           email:(NSString *)email;

/** Updates an account handle by DID. */
+ (BOOL)updateHandleWithContext:(PDSCLICommandContext *)context
                              did:(NSString *)did
                           handle:(NSString *)handle;

/** Updates the PLC service endpoint for an account DID. */
+ (BOOL)updatePlcEndpointWithContext:(PDSCLICommandContext *)context
                                  did:(NSString *)did
                          newEndpoint:(NSString *)newEndpoint;

/** Resolves the database path used by the CLI context. */
+ (NSString *)databasePathForContext:(PDSCLICommandContext *)context;
/** Resolves the PDS hostname used by the CLI context. */
+ (NSString *)pdsHostnameForContext:(PDSCLICommandContext *)context;
/** Resolves the public PDS service endpoint used by the CLI context. */
+ (NSString *)pdsServiceEndpointForContext:(PDSCLICommandContext *)context;

@end

NS_ASSUME_NONNULL_END

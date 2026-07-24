// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class ATProtoPermissionScope;
@class JWT;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Evaluates AT Protocol permission scopes against request contexts.
 *
 * @discussion Provides methods to extract permission scopes from OAuth JWTs and
 * evaluate them against XRPC method calls, record operations, blob uploads,
 * account access, and identity resolution. Supports the fail-open model: tokens
 * without any scopes permit all operations (backward compatibility).
 */
@interface ATProtoPermissionScopeEvaluator : NSObject

#pragma mark - Extraction

/**
 * Parse all permission scope strings from a space-separated scope claim.
 *
 * Filters out space: prefixes (handled by PDSSpaceScope) and returns
 * only standard resource-type scopes (repo:, rpc:, blob:, account:, identity:, include:).
 *
 * @param scopeString The JWT scope claim value (space-separated).
 * @return Array of parsed ATProtoPermissionScope objects. Empty if none found.
 */
+ (NSArray<ATProtoPermissionScope *> *)scopesFromScopeString:(NSString *)scopeString;

/**
 * Extract and parse permission scopes from a verified JWT.
 *
 * @param jwt A parsed JWT with a scope claim.
 * @return Array of parsed ATProtoPermissionScope objects. Empty if none found.
 */
+ (NSArray<ATProtoPermissionScope *> *)scopesFromJWT:(JWT *)jwt;

#pragma mark - RPC Scope Evaluation

/**
 * Check if any rpc: scope in the set authorizes the given method+audience.
 *
 * @param scopes Parsed permission scopes.
 * @param methodNSID The XRPC method NSID to check.
 * @param audience The service DID being called (nil for PDS-local calls).
 * @return YES if at least one rpc: scope matches, or if no rpc: scopes exist (fail-open).
 */
+ (BOOL)evaluateRPCScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                forMethod:(NSString *)methodNSID
                  audience:(nullable NSString *)audience;

#pragma mark - Repo Scope Evaluation

/**
 * Check if any repo: scope authorizes the given collection+action.
 *
 * @param scopes Parsed permission scopes.
 * @param collection The record collection NSID.
 * @param action The operation (create, update, delete).
 * @return YES if at least one repo: scope matches, or if no repo: scopes exist.
 */
+ (BOOL)evaluateRepoScopes:(NSArray<ATProtoPermissionScope *> *)scopes
              forCollection:(NSString *)collection
                     action:(NSString *)action;

#pragma mark - Blob Scope Evaluation

/**
 * Check if any blob: scope authorizes the given MIME type.
 *
 * @param scopes Parsed permission scopes.
 * @param mimeType The blob content type.
 * @return YES if at least one blob: scope matches, or if no blob: scopes exist.
 */
+ (BOOL)evaluateBlobScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                   forMIME:(NSString *)mimeType;

#pragma mark - Account Scope Evaluation

/**
 * Check if any account: scope authorizes the given attribute+action.
 *
 * @param scopes Parsed permission scopes.
 * @param attribute The account attribute (email, repo).
 * @param action The operation (read, manage).
 * @return YES if at least one account: scope matches, or if no account: scopes exist.
 */
+ (BOOL)evaluateAccountScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                 forAttribute:(NSString *)attribute
                       action:(nullable NSString *)action;

#pragma mark - Identity Scope Evaluation

/**
 * Check if any identity: scope authorizes the given attribute.
 *
 * @param scopes Parsed permission scopes.
 * @param attribute The identity attribute (handle, did).
 * @return YES if at least one identity: scope matches, or if no identity: scopes exist.
 */
+ (BOOL)evaluateIdentityScopes:(NSArray<ATProtoPermissionScope *> *)scopes
                  forAttribute:(NSString *)attribute;

@end

NS_ASSUME_NONNULL_END

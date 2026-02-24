//
//  XrpcIdentityHelper.h
//  ATProtoPDS
//
//  Identity resolution helper for XRPC endpoints.
//  Centralizes handle-to-DID resolution and DID document resolution logic.
//

#import <Foundation/Foundation.h>

@class HandleResolver;
@class PDSServiceDatabases;
@class PDSConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcIdentityHelper provides centralized identity resolution logic for XRPC endpoints.
 *
 * Responsibilities:
 * - Resolve handles to DIDs using HandleResolver
 * - Resolve account identifiers (handle or DID) to DIDs
 * - Resolve DID documents (PLC directory with local fallback)
 *
 * Handle Resolution Flow:
 * 1. Use HandleResolver service for DNS/HTTPS resolution
 * 2. Return DID or error
 *
 * Account Identifier Resolution:
 * 1. Detect if input is DID (starts with "did:") or handle
 * 2. Look up account in service database
 * 3. Return DID or error
 *
 * DID Resolution:
 * 1. For did:plc: Query PLC directory
 * 2. On PLC failure: Fallback to local account data
 * 3. For did:web: Construct from issuer
 * 4. Return DID document or error
 */
@interface XrpcIdentityHelper : NSObject

/**
 * Resolve handle to DID using HandleResolver.
 *
 * This is a synchronous wrapper around HandleResolver's async API.
 *
 * @param handle Handle to resolve (e.g., "alice.bsky.social")
 * @param resolver HandleResolver service for DNS/HTTPS resolution
 * @param error Error output parameter
 * @return Resolved DID or nil on failure
 */
+ (nullable NSString *)resolveHandleToDid:(NSString *)handle
                           handleResolver:(HandleResolver *)resolver
                                    error:(NSError **)error;

/**
 * Resolve account identifier (handle or DID) to DID.
 *
 * This method:
 * 1. Detects if identifier is a DID or handle
 * 2. Looks up account in service database
 * 3. Returns the account's DID
 *
 * @param identifier Account identifier (DID or handle)
 * @param serviceDatabases Service databases for account lookups
 * @param outDid Output parameter for resolved DID
 * @param error Error output parameter
 * @return YES if resolution succeeded, NO on failure
 */
+ (BOOL)resolveAccountIdentifierToDid:(NSString *)identifier
                     serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                               outDid:(NSString * _Nullable * _Nullable)outDid
                                error:(NSError **)error;

/**
 * Resolve DID document (PLC directory with local fallback).
 *
 * This method:
 * 1. For did:plc: Queries PLC directory
 * 2. On PLC failure: Falls back to local account data
 * 3. Returns DID document dictionary
 *
 * @param did DID to resolve
 * @param serviceDatabases Service databases for local fallback
 * @param configuration PDS configuration for PLC URL and service endpoint
 * @param error Error output parameter
 * @return DID document dictionary or nil on failure
 */
+ (nullable NSDictionary *)resolveDid:(NSString *)did
                     serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                        configuration:(PDSConfiguration *)configuration
                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

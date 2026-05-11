// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file DIDPLCResolver.h

 @abstract DID PLC resolution client for the AT Protocol.

 @discussion Provides synchronous and asynchronous resolution of did:plc DIDs
 against a PLC directory server. Includes configurable timeouts and caching.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for DID PLC resolver operations. */
extern NSString * const DIDPLCResolverErrorDomain;

/*!
 @enum DIDPLCResolverErrorCode

 @abstract Error codes for DID PLC resolution operations.

 @constant DIDPLCResolverErrorInvalidDID The DID format is invalid.
 @constant DIDPLCResolverErrorNotFound The DID was not found in the PLC directory.
 @constant DIDPLCResolverErrorNetworkError A network error occurred during resolution.
 @constant DIDPLCResolverErrorInvalidResponse The PLC server returned an invalid response.
 */
typedef NS_ENUM(NSInteger, DIDPLCResolverErrorCode) {
    DIDPLCResolverErrorInvalidDID = 1,
    DIDPLCResolverErrorNotFound = 2,
    DIDPLCResolverErrorNetworkError = 3,
    DIDPLCResolverErrorInvalidResponse = 4
};

/*!
 @class DIDPLCResolver

 @abstract A robust DID PLC Resolver with configurable timeouts and caching.

 @discussion
    Resolves did:plc DIDs against a PLC directory server (e.g., https://plc.directory).
    Supports both synchronous and asynchronous resolution with configurable timeouts.

    Thread Safety: All methods are thread-safe and can be called from any queue.
 */
@interface DIDPLCResolver : NSObject

/*! The base URL of the PLC server (e.g., https://plc.directory). */
@property (nonatomic, copy, readonly) NSString *plcUrl;

/*! The timeout interval for HTTP requests in seconds. Default is 5.0. */
@property (nonatomic, assign) NSTimeInterval timeout;

/*!
 @method initWithPlcUrl:

 @abstract Initializes the resolver with a specific PLC server URL.

 @param url The base URL string of the PLC server.

 @return A new resolver instance.
 */
- (instancetype)initWithPlcUrl:(NSString *)url NS_DESIGNATED_INITIALIZER;

/*!
 @method init

 @abstract Unavailable. Use initWithPlcUrl: instead.
 */
- (instancetype)init NS_UNAVAILABLE;

/*!
 @method resolveDID:error:

 @abstract Resolves a DID synchronously.

 @param did The DID (e.g. did:plc:...) to resolve.
 @param error A pointer to an error object that will be populated upon failure.
 @return The resolved DID document JSON dictionary, or nil if resolution failed or was not found.
 */
- (nullable NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error;

/*!
 @method resolveDID:completion:

 @abstract Resolves a DID asynchronously with optional backoff retries.

 @param did The DID to resolve.
 @param completion A block called when resolution is complete. Error is nil on success.
 */
- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary * _Nullable document, NSError * _Nullable error))completion;

/*!
 @method resolveAuditLogForDID:error:

 @abstract Synchronously fetches the audit log for a DID.

 @param did The DID to fetch the log for.
 @param error A pointer to an error object.
 @return An array of operations in the PLCs audit log, or nil on failure.
 */
- (nullable NSArray *)resolveAuditLogForDID:(NSString *)did error:(NSError **)error;

/*!
 @method resolveAuditLogForDID:completion:

 @abstract Asynchronously fetches the audit log for a DID.

 @param did The DID to fetch the log for.
 @param completion A block called with the audit log or an error.
 */
- (void)resolveAuditLogForDID:(NSString *)did completion:(void (^)(NSArray * _Nullable log, NSError * _Nullable error))completion;

/*!
 @method submitOperation:statusCode:error:

 @abstract Synchronously submits a PLC operation to the directory.

 @param operation The operation dictionary to submit.
 @param statusCode On return, the HTTP status code from the server.
 @param error A pointer to an error object.
 @return The raw response data from the server, or nil on network failure.
 */
- (nullable NSData *)submitOperation:(NSDictionary *)operation did:(NSString *)did statusCode:(NSInteger *)statusCode error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

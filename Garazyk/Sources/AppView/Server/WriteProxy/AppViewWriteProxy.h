// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewWriteProxy.h

 @abstract Proxies write requests from the AppView to the user's PDS.

 @discussion The AppView receives write requests (create/update/delete records)
 and forwards them to the user's PDS. This is the intended ATProto architecture:
 clients talk to the AppView, which proxies writes to the PDS.

 Write detection: if a procedure's input contains a $type field matching
 a record type, it's a write. Auto-detect create vs update by presence
 of uri field in input (no uri → create, has uri → update).

 SSRF protection: uses ATProtoSafeHTTPClient for all outbound requests.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;
@class HttpRequest;
@class HttpResponse;

extern NSErrorDomain const AppViewWriteProxyErrorDomain;

/*!
 */
typedef NS_ENUM(NSInteger, AppViewWriteProxyErrorCode) {
    AppViewWriteProxyErrorDIDResolutionFailed = 1,
    AppViewWriteProxyErrorPDSEndpointNotFound,
    AppViewWriteProxyErrorProxyRequestFailed,
    AppViewWriteProxyErrorNoAuthCredentials,
    AppViewWriteProxyErrorInvalidInput,
};

/*!
 @class AppViewWriteProxy

 @abstract Proxies write requests from the AppView to the user's PDS.
 */
@interface AppViewWriteProxy : NSObject

/*!
 @method initWithDatabase:plcUrl:

 @abstract Initialize with the AppView database and PLC URL.

 @param database The AppView database.
 @param plcUrl   The base URL of the PLC server.
 */
- (instancetype)initWithDatabase:(AppViewDatabase *)database
                          plcUrl:(nullable NSString *)plcUrl;

/*!
 @method proxyWriteRequest:response:nsid:callerDID:

 @abstract Proxy a write request to the caller's PDS.

 @param request   The original HTTP request.
 @param response  The HTTP response to populate with the PDS response.
 @param nsid      The NSID of the procedure being called.
 @param callerDID The authenticated caller's DID.
 */
- (void)proxyWriteRequest:(HttpRequest *)request
                  response:(HttpResponse *)response
                     nsid:(NSString *)nsid
                 callerDID:(NSString *)callerDID;

/*!
 @method isWriteProcedure:nsid:

 @abstract Determine if a procedure input represents a write operation.

 @param input The parsed procedure input body.
 @param nsid  The NSID of the procedure.

 @return YES if the input represents a write operation.
 */
- (BOOL)isWriteProcedure:(NSDictionary *)input nsid:(NSString *)nsid;

@end

NS_ASSUME_NONNULL_END

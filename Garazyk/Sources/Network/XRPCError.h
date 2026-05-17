// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XRPCError.h

 @abstract Error types for XRPC client-side error handling.

 @discussion Provides XRPCError class for parsing error responses from
 XRPC servers. Supports parsing error and message fields from JSON response
 bodies, matching the ATProto XRPC error format.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for XRPC errors. */
extern NSString * const XRPCErrorDomain;

/*!
 @class XRPCError

 @abstract Represents an XRPC error response.

 @discussion Parses error responses from XRPC servers. The error object
 contains an error code string and a human-readable message.
 */
@interface XRPCError : NSObject

/*! The error code string (e.g., "InvalidRequest", "AuthenticationRequired"). */
@property (nonatomic, copy, readonly) NSString *error;

/*! The detailed error message. */
@property (nonatomic, copy, readonly) NSString *message;

/*! The HTTP status code that triggered this error. */
@property (nonatomic, assign, readonly) NSInteger statusCode;

/*!
 @method errorWithData:statusCode:

 @abstract Creates an XRPCError from JSON data.

 @param data The JSON data containing error and message fields.
 @param statusCode The HTTP status code associated with this error.

 @return A new XRPCError instance, or nil if parsing fails.
 */
+ (nullable instancetype)errorWithData:(NSData *)data statusCode:(NSInteger)statusCode;

/*!
 @method errorWithDictionary:statusCode:

 @abstract Creates an XRPCError from a dictionary.

 @param dict The dictionary containing error and message fields.
 @param statusCode The HTTP status code associated with this error.

 @return A new XRPCError instance, or nil if parsing fails.
 */
+ (nullable instancetype)errorWithDictionary:(NSDictionary *)dict statusCode:(NSInteger)statusCode;

/*!
 @method initWithError:message:statusCode:

 @abstract Initializes an XRPCError with the given values.

 @param error The error code string.
 @param message The detailed error message.
 @param statusCode The HTTP status code.

 @return A new XRPCError instance.
 */
/**
 * @abstract Performs the initWithError operation.
 */
- (instancetype)initWithError:(NSString *)error
                      message:(NSString *)message
                   statusCode:(NSInteger)statusCode;

/*!
 @method toNSError

 @abstract Converts the XRPCError to an NSError.

 @return An NSError with the XRPCError domain and appropriate userInfo.
 */
- (NSError *)toNSError;

@end

NS_ASSUME_NONNULL_END

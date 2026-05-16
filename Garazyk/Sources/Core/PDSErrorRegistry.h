// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSErrorRegistry.h

 @abstract Central registry for PDS internal error codes and XRPC mappings.

 @discussion This header defines internal error codes for various PDS services
 and provides a mechanism to map these to standard AT Protocol / XRPC error strings.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! PDS Internal Error Domain */
extern NSErrorDomain const PDSErrorDomain;

/*!

 @abstract Internal error codes for the PDS.
 */
typedef NS_ENUM(NSInteger, PDSErrorCode) {
    PDSErrorUnknown = 0,
    
    // Auth Errors (1000-1999)
    PDSErrorInvalidToken = 1000,
    PDSErrorExpiredToken = 1001,
    PDSErrorInsufficientScope = 1002,
    PDSErrorInvalidSignature = 1003,
    PDSErrorDPoPVerificationFailed = 1004,
    
    // Account/Session Errors (2000-2999)
    PDSErrorAccountNotFound = 2000,
    PDSErrorInvalidCredentials = 2001,
    PDSErrorAccountDisabled = 2002,
    PDSErrorSessionExpired = 2003,
    
    // Repository/Record Errors (3000-3999)
    PDSErrorRepoNotFound = 3000,
    PDSErrorRecordNotFound = 3001,
    PDSErrorInvalidRecord = 3002,
    PDSErrorConcurrentWriteConflict = 3003,
    PDSErrorMSTCorruption = 3004,
    
    // Networking/System Errors (4000-4999)
    PDSErrorExternalServiceUnavailable = 4000,
    PDSErrorRateLimitExceeded = 4001,
    PDSErrorInternalDatabaseError = 4002,
};

/*!
 @function PDSErrorToXRPCError

 @abstract Maps an internal PDSErrorCode to an ATProto/XRPC error string.
 */
static inline NSString *PDSErrorToXRPCError(PDSErrorCode code) {
    switch (code) {
        case PDSErrorInvalidToken:
        case PDSErrorExpiredToken:
            return @"ExpiredToken";
        case PDSErrorInsufficientScope:
            return @"InsufficientScope";
        case PDSErrorAccountNotFound:
            return @"AccountNotFound";
        case PDSErrorInvalidCredentials:
            return @"InvalidCredentials";
        case PDSErrorRepoNotFound:
            return @"RepoNotFound";
        case PDSErrorRecordNotFound:
            return @"RecordNotFound";
        case PDSErrorInvalidRecord:
            return @"InvalidRecord";
        case PDSErrorRateLimitExceeded:
            return @"RateLimitExceeded";
        default:
            return @"InternalServerError";
    }
}

NS_ASSUME_NONNULL_END

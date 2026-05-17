// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoError.h
 
 @abstract Centralized error handling for ATProtoPDS.
 
 @discussion Defines the error domain and standard error codes used throughout the application.
 Provides factory methods for creating consistent error objects.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for generic ATProto errors. */
extern NSString * const ATProtoErrorDomain;

/*! key for userInfo dictionary containing the underlying cause (NSError or NSException) */
extern NSString * const ATProtoErrorUnderlyingCauseKey;

/*!
 @abstract Standard error codes.
 */
typedef NS_ENUM(NSInteger, ATProtoErrorCode) {
    ATProtoErrorCodeUnknown = 0,
    
    // Validation Errors (1000-1999)
    ATProtoErrorCodeInvalidInput = 1000,
    ATProtoErrorCodeMissingParameter,
    ATProtoErrorCodeValidationFailed,
    
    // Authentication/Authorization Errors (2000-2999)
    ATProtoErrorCodeUnauthorized = 2000,
    ATProtoErrorCodeForbidden,
    ATProtoErrorCodeSessionExpired,
    ATProtoErrorCodeInvalidCredentials,
    
    // Resource Errors (3000-3999)
    ATProtoErrorCodeNotFound = 3000,
    ATProtoErrorCodeAlreadyExists,
    ATProtoErrorCodeConflict,
    
    // Server/System Errors (5000-5999)
    ATProtoErrorCodeInternalServerError = 5000,
    ATProtoErrorCodeNotImplemented,
    ATProtoErrorCodeServiceUnavailable,
    ATProtoErrorCodeDatabaseError,
    
    // Network Errors (6000-6999)
    ATProtoErrorCodeNetworkError = 6000,
};

/**
 * @abstract Declares the ATProtoError public API.
 */
@interface ATProtoError : NSObject

/*!
 @method errorWithCode:message:
 @abstract Creates a simple error with a code and message.
 */
+ (NSError *)errorWithCode:(ATProtoErrorCode)code message:(NSString *)message;

/*!
 @method errorWithCode:message:underlyingError:
 @abstract Creates an error wrapping an underlying causal error.
 */
+ (NSError *)errorWithCode:(ATProtoErrorCode)code message:(NSString *)message underlyingError:(nullable NSError *)underlyingError;

/*!
 @method errorWithCode:message:userInfo:
 @abstract Creates an error with custom userInfo.
 */
+ (NSError *)errorWithCode:(ATProtoErrorCode)code message:(NSString *)message userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)userInfo;

/*!
 @method invalidInputWithError:
 @abstract Helper for invalid input errors.
 */
+ (NSError *)invalidInputWithMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END

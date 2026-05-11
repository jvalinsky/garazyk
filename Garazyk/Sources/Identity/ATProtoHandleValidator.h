// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHandleValidator.h

 @abstract Handle and email validation helpers for AT Protocol input.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain used for handle validation failures. */
extern NSString * const ATProtoHandleErrorDomain;
/*! Error domain used for email validation failures. */
extern NSString * const ATProtoEmailErrorDomain;

/*!
 @class ATProtoHandleValidator

 @abstract Validates and normalizes handle/email user input.
 */
@interface ATProtoHandleValidator : NSObject

/*!
 @method validateHandle:error:

 @abstract Validates a handle using ATProto/DNS constraints.

 @param handle Candidate handle string.
 @param error On failure, set to a descriptive validation error.
 @result YES when valid, otherwise NO.
 */
+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method normalizeHandle:

 @abstract Normalizes a valid handle to canonical form.

 @param handle Handle string.
 @result Lowercased canonical handle.
 */
+ (NSString *)normalizeHandle:(NSString *)handle;

/*!
 @method validateAndNormalizeHandle:error:

 @abstract Validates a handle, then returns its normalized form.

 @param handle Candidate handle string.
 @param error On failure, set to a descriptive validation error.
 @result Normalized handle, or nil if validation fails.
 */
+ (nullable NSString *)validateAndNormalizeHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method validateEmail:error:

 @abstract Validates basic email format/length constraints.

 @param email Candidate email string.
 @param error On failure, set to a descriptive validation error.
 @result YES when valid, otherwise NO.
 */
+ (BOOL)validateEmail:(NSString *)email error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

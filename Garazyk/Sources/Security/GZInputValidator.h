// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZInputValidator.h

 @abstract Input validation and sanitization for security.

 @discussion Provides validation for ATProto identifiers (DIDs, handles, NSIDs,
 URIs) and sanitization against common injection attacks (SQL, XSS, path traversal).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for validation failures. */
extern NSErrorDomain const GZValidationErrorDomain;

/*!

 @abstract Error codes for validation failures.

 @constant GZValidationErrorEmptyString Input was empty.
 @constant GZValidationErrorInvalidLength Input exceeds length limits.
 @constant GZValidationErrorInvalidFormat Input has invalid format.
 @constant GZValidationErrorContainsReservedChars Input contains reserved characters.
 @constant GZValidationErrorOverflow Numeric overflow detected.
 @constant GZValidationErrorInvalidNSID Invalid NSID format.
 @constant GZValidationErrorInvalidDID Invalid DID format.
 @constant GZValidationErrorInvalidHandle Invalid handle format.
 @constant GZValidationErrorInvalidURI Invalid URI format.
 @constant GZValidationErrorNullByteInjection Null byte injection attempt.
 */
/**
 * @abstract Defines GZValidationError values exposed by this API.
 */
typedef NS_ENUM(NSInteger, GZValidationError) {
    GZValidationErrorEmptyString = 1000,
    GZValidationErrorInvalidLength = 1001,
    GZValidationErrorInvalidFormat = 1002,
    GZValidationErrorContainsReservedChars = 1003,
    GZValidationErrorOverflow = 1004,
    GZValidationErrorInvalidNSID = 1005,
    GZValidationErrorInvalidDID = 1006,
    GZValidationErrorInvalidHandle = 1007,
    GZValidationErrorInvalidURI = 1008,
    GZValidationErrorNullByteInjection = 1010,
};

/*!
 @class GZInputValidator

 @abstract Validates and sanitizes user input.

 @discussion Provides validation methods for ATProto identifiers and
 sanitization against injection attacks.
 */
@interface GZInputValidator : NSObject

/*! Returns the shared validator instance. */
+ (instancetype)sharedValidator;

/*! Validates an NSID (e.g., app.bsky.feed.post). */
- (BOOL)isValidNSID:(NSString *)nsid;

/*! Validates a DID (e.g., did:plc:...). */
- (BOOL)isValidDID:(NSString *)did;

/*! Validates a handle (e.g., alice.test). */
- (BOOL)isValidHandle:(NSString *)handle;

/*! Validates a record key. */
- (BOOL)isValidRecordKey:(NSString *)rkey;

/*! Validates a TID. */
- (BOOL)isValidTID:(NSString *)tid;

/*! Validates a CID string. */
- (BOOL)isValidCID:(NSString *)cid;

/*! Validates a collection name. */
- (BOOL)isValidCollectionName:(NSString *)collection;

/*! Validates a repo URI. */
- (BOOL)isValidRepoURI:(NSString *)uri;

/*! Validates an AT URI. */
- (BOOL)isValidATURI:(NSString *)uri;

/*! Checks for null byte injection. */
- (BOOL)containsNullByte:(NSString *)input;

/*! Validates and clamps a limit parameter. */
- (NSInteger)validateLimitParameter:(NSInteger)limit maxLimit:(NSInteger)maxLimit;

/*! Validates a cursor parameter. */
- (nullable NSString *)validateCursorParameter:(NSString *)cursor maxLength:(NSInteger)maxLength;

@end

NS_ASSUME_NONNULL_END

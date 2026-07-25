// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract Input validation and sanitization for security.
 *
 * @discussion Provides validation for ATProto identifiers (DIDs, handles, NSIDs,
 * URIs) and sanitization against common injection attacks (SQL, XSS, path traversal).
 */

#import <Foundation/Foundation.h>
#import "Compat/PDSTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for validation failures.
 */
extern NSErrorDomain const GZValidationErrorDomain;

/**
 * @abstract Error codes for validation failures.
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

/**
 * @abstract Validates and sanitizes user input.
 *
 * @discussion Provides validation methods for ATProto identifiers and
 * sanitization against injection attacks.
 */
@interface GZInputValidator : NSObject

/**
 * @abstract Returns the shared validator instance.
 */
+ (instancetype)sharedValidator;

/**
 * @abstract Validates an NSID (e.g., app.bsky.feed.post).
 */
- (BOOL)isValidNSID:(NSString *)nsid;

/**
 * @abstract Validates a DID (e.g., did:plc:...).
 */
- (BOOL)isValidDID:(NSString *)did;

/**
 * @abstract Validates a handle (e.g., alice.test).
 */
- (BOOL)isValidHandle:(NSString *)handle;

/**
 * @abstract Validates a record key.
 */
- (BOOL)isValidRecordKey:(NSString *)rkey;

/**
 * @abstract Validates a TID.
 */
- (BOOL)isValidTID:(NSString *)tid;

/**
 * @abstract Validates a CID string.
 */
- (BOOL)isValidCID:(NSString *)cid;

/**
 * @abstract Validates a collection name.
 */
- (BOOL)isValidCollectionName:(NSString *)collection;

/**
 * @abstract Validates a repo URI.
 */
- (BOOL)isValidRepoURI:(NSString *)uri;

/**
 * @abstract Validates an AT URI.
 */
- (BOOL)isValidATURI:(NSString *)uri;

/**
 * @abstract Checks for null byte injection.
 */
- (BOOL)containsNullByte:(NSString *)input;

/**
 * @abstract Validates and clamps a limit parameter.
 */
- (NSInteger)validateLimitParameter:(NSInteger)limit maxLimit:(NSInteger)maxLimit;

/**
 * @abstract Validates a cursor parameter.
 */
- (nullable NSString *)validateCursorParameter:(NSString *)cursor maxLength:(NSInteger)maxLength;

@end

NS_ASSUME_NONNULL_END

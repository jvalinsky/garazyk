/*!
 @file PDSInputValidator.h

 @abstract Input validation and sanitization for security.

 @discussion Provides validation for ATProto identifiers (DIDs, handles, NSIDs,
 URIs) and sanitization against common injection attacks (SQL, XSS, path traversal).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for validation failures. */
extern NSErrorDomain const PDSValidationErrorDomain;

/*!
 @enum PDSValidationError

 @abstract Error codes for validation failures.

 @constant PDSValidationErrorEmptyString Input was empty.
 @constant PDSValidationErrorInvalidLength Input exceeds length limits.
 @constant PDSValidationErrorInvalidFormat Input has invalid format.
 @constant PDSValidationErrorContainsReservedChars Input contains reserved characters.
 @constant PDSValidationErrorOverflow Numeric overflow detected.
 @constant PDSValidationErrorInvalidNSID Invalid NSID format.
 @constant PDSValidationErrorInvalidDID Invalid DID format.
 @constant PDSValidationErrorInvalidHandle Invalid handle format.
 @constant PDSValidationErrorInvalidURI Invalid URI format.
 @constant PDSValidationErrorPathTraversal Path traversal attempt detected.
 @constant PDSValidationErrorNullByteInjection Null byte injection attempt.
 @constant PDSValidationErrorSQLInjectionPattern SQL injection pattern detected.
 @constant PDSValidationErrorXSSPattern XSS pattern detected.
 */
typedef NS_ENUM(NSInteger, PDSValidationError) {
    PDSValidationErrorEmptyString = 1000,
    PDSValidationErrorInvalidLength = 1001,
    PDSValidationErrorInvalidFormat = 1002,
    PDSValidationErrorContainsReservedChars = 1003,
    PDSValidationErrorOverflow = 1004,
    PDSValidationErrorInvalidNSID = 1005,
    PDSValidationErrorInvalidDID = 1006,
    PDSValidationErrorInvalidHandle = 1007,
    PDSValidationErrorInvalidURI = 1008,
    PDSValidationErrorPathTraversal = 1009,
    PDSValidationErrorNullByteInjection = 1010,
    PDSValidationErrorSQLInjectionPattern = 1011,
    PDSValidationErrorXSSPattern = 1012,
};

/*!
 @class PDSInputValidator

 @abstract Validates and sanitizes user input.

 @discussion Provides validation methods for ATProto identifiers and
 sanitization against injection attacks.
 */
@interface PDSInputValidator : NSObject

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

/*! Sanitizes input for SQL queries. @deprecated Use parameterized queries instead. */
- (nullable NSString *)sanitizeSQLInput:(NSString *)input error:(NSError **)error DEPRECATED_MSG_ATTRIBUTE("Use parameterized queries instead.");

/*! Sanitizes input for file paths. @deprecated Use strict whitelist validation instead. */
- (nullable NSString *)sanitizePathInput:(NSString *)input error:(NSError **)error DEPRECATED_MSG_ATTRIBUTE("Use strict whitelist validation instead.");

/*! Sanitizes input for JSON fields. @deprecated Lexicon validation handles this at the application layer. */
- (nullable NSString *)sanitizeJSONField:(NSString *)input error:(NSError **)error DEPRECATED_MSG_ATTRIBUTE("Lexicon validation handles this at the application layer.");

/*! Checks for SQL injection patterns. @deprecated Fragile blacklist-based security. */
- (BOOL)containsSQLInjectionPattern:(NSString *)input DEPRECATED_MSG_ATTRIBUTE("Fragile blacklist-based security. Use parameterized queries.");

/*! Checks for path traversal patterns. @deprecated Use strict whitelist validation instead. */
- (BOOL)containsPathTraversalPattern:(NSString *)input DEPRECATED_MSG_ATTRIBUTE("Use strict whitelist validation instead.");

/*! Checks for null byte injection. */
- (BOOL)containsNullByte:(NSString *)input;

/*! Checks for XSS patterns. @deprecated Lexicon validation handles this. */
- (BOOL)containsXSSPattern:(NSString *)input DEPRECATED_MSG_ATTRIBUTE("Lexicon validation handles this.");

/*! Validates and clamps a limit parameter. */
- (NSInteger)validateLimitParameter:(NSInteger)limit maxLimit:(NSInteger)maxLimit;

/*! Validates a cursor parameter. */
- (nullable NSString *)validateCursorParameter:(NSString *)cursor maxLength:(NSInteger)maxLength;

@end

NS_ASSUME_NONNULL_END

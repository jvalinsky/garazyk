#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PDSValidationErrorDomain;

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

@interface PDSInputValidator : NSObject

+ (instancetype)sharedValidator;

- (BOOL)isValidNSID:(NSString *)nsid;
- (BOOL)isValidDID:(NSString *)did;
- (BOOL)isValidHandle:(NSString *)handle;
- (BOOL)isValidRecordKey:(NSString *)rkey;
- (BOOL)isValidTID:(NSString *)tid;
- (BOOL)isValidCID:(NSString *)cid;
- (BOOL)isValidCollectionName:(NSString *)collection;
- (BOOL)isValidRepoURI:(NSString *)uri;
- (BOOL)isValidATURI:(NSString *)uri;

- (nullable NSString *)sanitizeSQLInput:(NSString *)input error:(NSError **)error;
- (nullable NSString *)sanitizePathInput:(NSString *)input error:(NSError **)error;
- (nullable NSString *)sanitizeJSONField:(NSString *)input error:(NSError **)error;

- (BOOL)containsSQLInjectionPattern:(NSString *)input;
- (BOOL)containsPathTraversalPattern:(NSString *)input;
- (BOOL)containsNullByte:(NSString *)input;
- (BOOL)containsXSSPattern:(NSString *)input;

- (NSInteger)validateLimitParameter:(NSInteger)limit maxLimit:(NSInteger)maxLimit;
- (nullable NSString *)validateCursorParameter:(NSString *)cursor maxLength:(NSInteger)maxLength;

@end

NS_ASSUME_NONNULL_END

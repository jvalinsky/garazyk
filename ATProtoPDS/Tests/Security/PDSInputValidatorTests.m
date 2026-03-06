#import <XCTest/XCTest.h>
#import "Security/PDSInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSInputValidatorTests : XCTestCase
@property (nonatomic, strong, nullable) PDSInputValidator *validator;
@end

@implementation PDSInputValidatorTests

- (void)setUp {
    [super setUp];
    self.validator = [PDSInputValidator sharedValidator];
}

- (void)tearDown {
    self.validator = nil;
    [super tearDown];
}

- (void)testIdentifierValidationBasics {
    XCTAssertTrue([self.validator isValidNSID:@"com.atproto.server"]);
    XCTAssertFalse([self.validator isValidNSID:@"app.bsky"]);

    XCTAssertTrue([self.validator isValidDID:@"did:plc:abc123"]);
    XCTAssertFalse([self.validator isValidDID:@"did:plc:"]);

    XCTAssertTrue([self.validator isValidHandle:@"user.example.com"]);
    XCTAssertFalse([self.validator isValidHandle:@"-bad.example.com"]);

    XCTAssertTrue([self.validator isValidATURI:@"at://did_plc_abc123/app_bsky_feed_post/abc"]);
    XCTAssertFalse([self.validator isValidATURI:@"at://did_plc_abc123/../bad"]);
}

- (void)testRecordKeyAndTidValidation {
    XCTAssertTrue([self.validator isValidTID:@"234567abcdefg"]);
    XCTAssertTrue([self.validator isValidRecordKey:@"234567abcdefg"]);
    XCTAssertTrue([self.validator isValidRecordKey:@"alpha_beta/123"]);
    XCTAssertFalse([self.validator isValidRecordKey:@"../escape"]);
}

- (void)testNullByteDetection {
    const char bytes[] = {'a', 'b', '\0', 'c'};
    NSString *stringWithNull = [[NSString alloc] initWithBytes:bytes length:4 encoding:NSUTF8StringEncoding];
    XCTAssertNotNil(stringWithNull);
    XCTAssertTrue([self.validator containsNullByte:stringWithNull]);
    XCTAssertFalse([self.validator isValidHandle:stringWithNull]);
}

- (void)testSanitizeSQLInput {
    // Note: Traditional SQL sanitization (quote escaping) is deprecated.
    // We now rely on parameterized queries. Sanitize only removes null bytes.
    NSError *error = nil;
    NSString *input = @"O'Reilly";
    NSString *sanitized = [self.validator sanitizeSQLInput:input error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(sanitized, @"O'Reilly"); // No longer escapes quotes

    // Redundant pattern blocking is removed.
    NSString *query = @"1; DROP TABLE users";
    NSString *sanitizedQuery = [self.validator sanitizeSQLInput:query error:nil];
    XCTAssertEqualObjects(sanitizedQuery, query); // No longer blocks patterns
    
    // Test null byte removal
    const char bytes[] = {'u', 's', 'e', 'r', '\0', '1'};
    NSString *withNull = [[NSString alloc] initWithBytes:bytes length:6 encoding:NSUTF8StringEncoding];
    NSString *sanitizedNull = [self.validator sanitizeSQLInput:withNull error:nil];
    XCTAssertEqualObjects(sanitizedNull, @"user1");
}

- (void)testSanitizePathInput {
    // Note: Path sanitization now primarily handles null bytes and obvious traversal.
    NSError *error = nil;
    NSString *sanitized = [self.validator sanitizePathInput:@"safe/path/file.txt" error:&error];
    XCTAssertEqualObjects(sanitized, @"safe/path/file.txt");

    // We still block basic traversal if containsPathTraversalPattern is called
    XCTAssertTrue([self.validator containsPathTraversalPattern:@"../etc/passwd"]);
}

- (void)testSanitizeJSONField {
    // Note: HTML escaping is deprecated at this layer.
    NSError *error = nil;
    NSString *input = @"Hello <b>world</b>";
    NSString *sanitized = [self.validator sanitizeJSONField:input error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(sanitized, input); // No longer escapes HTML

    // Test null byte removal
    const char bytes[] = {'{', '}', '\0'};
    NSString *withNull = [[NSString alloc] initWithBytes:bytes length:3 encoding:NSUTF8StringEncoding];
    NSString *sanitizedNull = [self.validator sanitizeJSONField:withNull error:nil];
    XCTAssertEqualObjects(sanitizedNull, @"{}");
}

- (void)testLimitAndCursorValidation {
    XCTAssertEqual([self.validator validateLimitParameter:0 maxLimit:50], 20);
    XCTAssertEqual([self.validator validateLimitParameter:500 maxLimit:50], 50);
    XCTAssertEqual([self.validator validateLimitParameter:25 maxLimit:50], 25);

    XCTAssertNil([self.validator validateCursorParameter:@"invalid-" maxLength:10]);
    XCTAssertNil([self.validator validateCursorParameter:@"toolongcursor" maxLength:5]);
    XCTAssertEqualObjects([self.validator validateCursorParameter:@"abcd+/==" maxLength:16], @"abcd+/==");
}

- (void)testCIDCollectionAndRepoValidation {
    XCTAssertTrue([self.validator isValidCID:@"bafybeigdyrztxqzjz"]);
    XCTAssertFalse([self.validator isValidCID:@"zafybeigdyrztx3f4z3q4w2j2qk4m6j2z7y7qzj7jz5h3z2w4z6a7b8c9d"]);
    XCTAssertFalse([self.validator isValidCID:@"bshort"]);

    XCTAssertTrue([self.validator isValidCollectionName:@"com.atproto.server"]);
    XCTAssertFalse([self.validator isValidCollectionName:@"not-a-nsid"]);

    XCTAssertTrue([self.validator isValidRepoURI:@"at://did_plc_abc123/app_bsky_feed_post/abc"]);
    XCTAssertFalse([self.validator isValidRepoURI:@"at://did_plc_abc123/../bad"]);
}

- (void)testPatternDetectionHelpers {
    // Legacy SQL and XSS pattern detection are deprecated and return NO.
    XCTAssertFalse([self.validator containsSQLInjectionPattern:@"select * from users UNION SELECT password"]);
    
    // Path traversal detection is still active as it's less fragile than SQL/XSS blacklists.
    XCTAssertTrue([self.validator containsPathTraversalPattern:@"..%2Fetc/passwd"]);
    XCTAssertTrue([self.validator containsPathTraversalPattern:@"a/../b"]);
    XCTAssertFalse([self.validator containsPathTraversalPattern:@"safe/path"]);

    XCTAssertFalse([self.validator containsXSSPattern:@"javascript:alert(1)"]);
}

- (void)testSanitizersBlockNilInputWithError {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    NSError *sqlError = nil;
    XCTAssertNil([self.validator sanitizeSQLInput:nil error:&sqlError]);
    XCTAssertNotNil(sqlError);
    XCTAssertEqual(sqlError.code, PDSValidationErrorEmptyString);

    NSError *pathError = nil;
    XCTAssertNil([self.validator sanitizePathInput:nil error:&pathError]);
    XCTAssertNotNil(pathError);
    XCTAssertEqual(pathError.code, PDSValidationErrorEmptyString);

    NSError *jsonError = nil;
    XCTAssertNil([self.validator sanitizeJSONField:nil error:&jsonError]);
    XCTAssertNotNil(jsonError);
    XCTAssertEqual(jsonError.code, PDSValidationErrorEmptyString);
#pragma clang diagnostic pop
}

@end

NS_ASSUME_NONNULL_END

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
    XCTAssertTrue([self.validator isValidNSID:@"app.bsky.feed.post"]);
    XCTAssertFalse([self.validator isValidNSID:@"app.bsky"]);

    XCTAssertTrue([self.validator isValidDID:@"did:plc:abc123"]);
    XCTAssertFalse([self.validator isValidDID:@"did:plc:"]);

    XCTAssertTrue([self.validator isValidHandle:@"user.example.com"]);
    XCTAssertFalse([self.validator isValidHandle:@"-bad.example.com"]);

    XCTAssertTrue([self.validator isValidATURI:@"at://did:plc:abc123/app.bsky.feed.post/abc"]);
    XCTAssertFalse([self.validator isValidATURI:@"at://did:plc:abc123/../bad"]);
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
    NSError *error = nil;
    NSString *sanitized = [self.validator sanitizeSQLInput:@"O'Reilly" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(sanitized, @"O''Reilly");

    NSError *blockedError = nil;
    NSString *blocked = [self.validator sanitizeSQLInput:@"1; DROP TABLE users" error:&blockedError];
    XCTAssertNil(blocked);
    XCTAssertNotNil(blockedError);
}

- (void)testSanitizePathInput {
    NSError *error = nil;
    NSString *sanitized = [self.validator sanitizePathInput:@"safe/path/file.txt" error:&error];
    XCTAssertEqualObjects(sanitized, @"safe/path/file.txt");

    NSError *blockedError = nil;
    NSString *blocked = [self.validator sanitizePathInput:@"../etc/passwd" error:&blockedError];
    XCTAssertNil(blocked);
    XCTAssertNotNil(blockedError);
}

- (void)testSanitizeJSONField {
    NSError *error = nil;
    NSString *sanitized = [self.validator sanitizeJSONField:@"Hello <b>world</b>" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(sanitized, @"Hello &lt;b&gt;world&lt;/b&gt;");

    NSError *blockedError = nil;
    NSString *blocked = [self.validator sanitizeJSONField:@"<script>alert(1)</script>" error:&blockedError];
    XCTAssertNil(blocked);
    XCTAssertNotNil(blockedError);
}

- (void)testLimitAndCursorValidation {
    XCTAssertEqual([self.validator validateLimitParameter:0 maxLimit:50], 20);
    XCTAssertEqual([self.validator validateLimitParameter:500 maxLimit:50], 50);
    XCTAssertEqual([self.validator validateLimitParameter:25 maxLimit:50], 25);

    XCTAssertNil([self.validator validateCursorParameter:@"invalid-" maxLength:10]);
    XCTAssertNil([self.validator validateCursorParameter:@"toolongcursor" maxLength:5]);
    XCTAssertEqualObjects([self.validator validateCursorParameter:@"abcd+/==" maxLength:16], @"abcd+/==");
}

@end

NS_ASSUME_NONNULL_END

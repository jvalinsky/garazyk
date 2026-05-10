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

@end

NS_ASSUME_NONNULL_END

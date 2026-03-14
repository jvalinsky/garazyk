// Tests for ATProtoValidator: DID, handle, CID, TID, and NSID validation.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Core/ATProtoValidator.h"

@interface ATProtoValidatorTests : XCTestCase
@end

@implementation ATProtoValidatorTests

#pragma mark - DID

- (void)testValidPlcDIDPassesValidation {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateDID:@"did:plc:abc123xyz456" error:&error];
    XCTAssertTrue(ok, @"Valid did:plc: must pass: %@", error);
}

- (void)testValidWebDIDPassesValidation {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateDID:@"did:web:pds.example.com" error:&error];
    XCTAssertTrue(ok, @"Valid did:web: must pass: %@", error);
}

- (void)testInvalidDIDMissingMethodFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateDID:@"notadid" error:&error];
    XCTAssertFalse(ok, @"String without 'did:' prefix must fail");
    XCTAssertNotNil(error);
}

- (void)testEmptyDIDFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateDID:@"" error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
}

- (void)testDIDWithSpacesFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateDID:@"did:plc:abc 123" error:&error];
    XCTAssertFalse(ok, @"DID with spaces must fail");
}

#pragma mark - Handle

- (void)testValidHandlePassesValidation {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateHandle:@"alice.test" error:&error];
    XCTAssertTrue(ok, @"'alice.test' is a valid handle: %@", error);
}

- (void)testValidBskySocialHandlePasses {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateHandle:@"alice.bsky.social" error:&error];
    XCTAssertTrue(ok, @"'alice.bsky.social' must pass: %@", error);
}

- (void)testHandleWithoutDotFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateHandle:@"alice" error:&error];
    XCTAssertFalse(ok, @"Handle without a dot must fail");
}

- (void)testHandleWithSpacesFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateHandle:@"alice bsky.social" error:&error];
    XCTAssertFalse(ok, @"Handle with spaces must fail");
}

- (void)testEmptyHandleFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateHandle:@"" error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
}

#pragma mark - CID

- (void)testValidCIDv1Passes {
    NSError *error = nil;
    // A real bafkrei-prefixed CIDv1 (raw SHA-256)
    BOOL ok = [ATProtoValidator validateCID:@"bafkreihdwdcefgh4dqkjv67uzcmw37nwp76ccraskalqkqsrv6bpnsh7"
                                      error:&error];
    XCTAssertTrue(ok, @"Valid CIDv1 must pass: %@", error);
}

- (void)testEmptyCIDFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateCID:@"" error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
}

- (void)testRandomStringCIDFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateCID:@"notacid!!!!" error:&error];
    XCTAssertFalse(ok, @"Garbage string must fail CID validation");
}

#pragma mark - TID

- (void)testValidTIDPasses {
    NSError *error = nil;
    // 13-char base32-sortable string in valid TID range
    BOOL ok = [ATProtoValidator validateTID:@"3jzfcijpj2z2a" error:&error];
    XCTAssertTrue(ok, @"13-char TID must pass: %@", error);
}

- (void)testTIDTooShortFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateTID:@"abc" error:&error];
    XCTAssertFalse(ok, @"TID shorter than 13 chars must fail");
}

- (void)testTIDTooLongFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateTID:@"aaaaaaaaaaaaaaaaa" error:&error]; // 17 chars
    XCTAssertFalse(ok, @"TID longer than 13 chars must fail");
}

- (void)testTIDWithInvalidCharsFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateTID:@"UPPERCASE_FAIL!" error:&error];
    XCTAssertFalse(ok, @"TID with invalid chars must fail");
}

#pragma mark - NSID

- (void)testValidNSIDPasses {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateNSID:@"app.bsky.feed.post" error:&error];
    XCTAssertTrue(ok, @"'app.bsky.feed.post' is a valid NSID: %@", error);
}

- (void)testNSIDWithTwoComponentsPasses {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateNSID:@"com.example.doSomething" error:&error];
    XCTAssertTrue(ok, @"Three-segment NSID must pass: %@", error);
}

- (void)testNSIDWithoutDotsFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateNSID:@"invalid" error:&error];
    XCTAssertFalse(ok, @"NSID without dots must fail");
}

- (void)testNSIDWithSpacesFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateNSID:@"app.bsky feed.post" error:&error];
    XCTAssertFalse(ok, @"NSID with spaces must fail");
}

- (void)testEmptyNSIDFails {
    NSError *error = nil;
    BOOL ok = [ATProtoValidator validateNSID:@"" error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
}

@end

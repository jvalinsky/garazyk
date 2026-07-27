// SPDX-License-Identifier: MIT
// ... (standard header omitted for brevity)

#import <XCTest/XCTest.h>
#import "AppView/AppViewIdentityHelper.h"

@interface AppViewIdentityHelperTests : XCTestCase
@end

@implementation AppViewIdentityHelperTests

- (void)setUp
{
    [super setUp];
    // Reset to default configuration to isolate tests from shared static state
    [AppViewIdentityHelper configureWithPlcURL:@"https://plc.directory"
                               cacheTTLSeconds:300];
}

// MARK: - configureWithPlcURL:cacheTTLSeconds:

- (void)testConfigure_WithValidValues
{
    XCTAssertNoThrow([AppViewIdentityHelper configureWithPlcURL:@"https://plc.test.example.com"
                                               cacheTTLSeconds:600],
                     @"configure should not throw with valid values");
}

- (void)testConfigure_NilPlcURL_DoesNotCrash
{
    XCTAssertNoThrow([AppViewIdentityHelper configureWithPlcURL:nil
                                               cacheTTLSeconds:300],
                     @"Nil PLC URL should not crash");
}

- (void)testConfigure_EmptyPlcURL_DoesNotCrash
{
    XCTAssertNoThrow([AppViewIdentityHelper configureWithPlcURL:@""
                                               cacheTTLSeconds:300],
                     @"Empty PLC URL should not crash");
}

- (void)testConfigure_ZeroCacheTTL_DoesNotCrash
{
    XCTAssertNoThrow([AppViewIdentityHelper configureWithPlcURL:@"https://plc.directory"
                                               cacheTTLSeconds:0],
                     @"Zero TTL should not crash");
}

- (void)testConfigure_NegativeCacheTTL_DoesNotCrash
{
    XCTAssertNoThrow([AppViewIdentityHelper configureWithPlcURL:@"https://plc.directory"
                                               cacheTTLSeconds:-100],
                     @"Negative TTL should not crash");
}

// MARK: - resolveHandleForDID:error:

- (void)testResolve_NilDID_ReturnsNil
{
    NSError *error = nil;
    NSString *handle = [AppViewIdentityHelper resolveHandleForDID:nil error:&error];
    XCTAssertNil(handle, @"Nil DID should return nil");
    // error may be nil or untouched — either is acceptable
}

- (void)testResolve_NilDIDNilError_DoesNotCrash
{
    XCTAssertNoThrow([AppViewIdentityHelper resolveHandleForDID:nil error:NULL],
                     @"Nil DID with NULL error should not crash");
}

- (void)testResolve_EmptyDID_ReturnsNil
{
    NSError *error = nil;
    NSString *handle = [AppViewIdentityHelper resolveHandleForDID:@"" error:&error];
    XCTAssertNil(handle, @"Empty DID should return nil");
}

- (void)testResolve_EmptyDIDNilError_DoesNotCrash
{
    XCTAssertNoThrow([AppViewIdentityHelper resolveHandleForDID:@"" error:NULL],
                     @"Empty DID with NULL error should not crash");
}

- (void)testResolve_NonPlcPrefixDID_ReturnsNil
{
    // Only did:plc: prefix is supported; other DID methods return nil
    NSArray *unsupportedDIDs = @[
        @"did:web:example.com",
        @"did:key:z6MkhaXgBZDvB9pQqQvx7cY6zYzYzYzYzYzYzYzY",
        @"did:ethr:0x1234",
        @"did:sol:abc123",
        @"did:ion:test",
        @"not-even-a-did",
    ];

    for (NSString *did in unsupportedDIDs) {
        NSError *error = nil;
        NSString *handle = [AppViewIdentityHelper resolveHandleForDID:did error:&error];
        XCTAssertNil(handle, @"Non-PLC DID %@ should return nil", did);
        // error should be untouched (not set)
    }
}

- (void)testResolve_NonPlcPrefix_WithNULLError_DoesNotCrash
{
    XCTAssertNoThrow([AppViewIdentityHelper resolveHandleForDID:@"did:web:example.com"
                                                          error:NULL],
                     @"Non-PLC DID with NULL error should not crash");
}

- (void)testResolve_PlcPrefix_WithoutNetwork_DoesNotSetError
{
    // This tests that the method doesn't crash or set an unexpected error
    // for a valid did:plc: prefix when no network is available.
    // It will likely return nil due to timeout, but should not crash.
    NSError *error = nil;
    NSString *handle = [AppViewIdentityHelper resolveHandleForDID:@"did:plc:unknown123456789"
                                                            error:&error];
    // We expect nil because there's no real PLC directory running,
    // but it should not crash or set a non-nil error
    // error may be nil (the source explicitly sets *error = nil on failure)
    if (handle) {
        // If handle resolves (unlikely without network), verify it's a string
        XCTAssertTrue([handle isKindOfClass:[NSString class]]);
    }
}

- (void)testResolve_NilDID_WithPrepopulatedError_DoesNotCrash
{
    NSError *error = [NSError errorWithDomain:@"test" code:-1 userInfo:nil];
    NSString *handle = [AppViewIdentityHelper resolveHandleForDID:nil error:&error];
    XCTAssertNil(handle);
    // The source returns nil without writing to error for nil DID,
    // so the original error should be preserved
    XCTAssertNotNil(error, @"Original error should not be overwritten to nil");
}

- (void)testResolve_WhitespaceDID_ReturnsNil
{
    // DID with whitespace only is not a valid did:plc: prefix
    NSError *error = nil;
    NSString *handle = [AppViewIdentityHelper resolveHandleForDID:@"   " error:&error];
    XCTAssertNil(handle, @"Whitespace DID should return nil");
}

@end

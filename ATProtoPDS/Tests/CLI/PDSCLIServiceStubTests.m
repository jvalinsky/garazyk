#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDispatcher.h"
#import "CLI/PDSCLIInputHelper.h"
#import "CLI/PDSCLIAccountManager.h"

@interface PDSCLIServiceStubTests : XCTestCase
@end

@implementation PDSCLIServiceStubTests

- (void)testSharedStubDefaultsEqualExpected {
    PDSCLIServiceStub *stub = [PDSCLIServiceStub sharedStub];
    XCTAssertEqualObjects(stub.serviceDid, @"did:plc:service-stub");
    XCTAssertEqualObjects(stub.serviceHost, @"localhost");
}

- (void)testPayloadIncludesOptionalFields {
    PDSCLIServiceStub *stub = [PDSCLIServiceStub sharedStub];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *payload = [stub payloadForAudience:@"did:web:example.com" method:@"com.example.command" expiry:now + 60];

    XCTAssertEqualObjects(payload[@"iss"], stub.serviceDid);
    XCTAssertEqualObjects(payload[@"aud"], @"did:web:example.com");
    XCTAssertEqualObjects(payload[@"lxm"], @"com.example.command");
    XCTAssertEqualObjects(payload[@"serviceHost"], stub.serviceHost);
    XCTAssertEqualObjects(payload[@"exp"], @((long long)(now + 60)));
}

- (void)testCustomPayloadProviderOverridesDefaults {
    PDSCLIServiceStub *stub = [PDSCLIServiceStub sharedStub];
    stub.payloadProvider = ^NSDictionary<NSString *,id> *(NSString *audience, NSString *method, NSTimeInterval expiry) {
        return @{
            @"iss": @"override",
            @"aud": audience ?: @"missing",
            @"exp": @((long long)floor(expiry)),
            @"custom": method ?: @"none"
        };
    };

    NSDictionary *payload = [stub payloadForAudience:@"did:web:override" method:nil expiry:1234];
    XCTAssertEqualObjects(payload[@"iss"], @"override");
    XCTAssertEqualObjects(payload[@"aud"], @"did:web:override");
    XCTAssertEqualObjects(payload[@"custom"], @"none");
    XCTAssertEqualObjects(payload[@"exp"], @(1234LL));

    stub.payloadProvider = nil;
}

// MARK: - Priority 7: PDSCLIInputHelper tests

- (void)testInputHelperIsNonInteractiveInTestEnvironment {
    // PDS_NON_INTERACTIVE or non-TTY stdin means isInteractiveTTY returns NO.
    setenv("PDS_NON_INTERACTIVE", "1", 1);
    BOOL interactive = [PDSCLIInputHelper isInteractiveTTY];
    XCTAssertFalse(interactive, @"Should be non-interactive when PDS_NON_INTERACTIVE=1");
}

- (void)testInputHelperDefaultValueReturnedWhenNonInteractive {
    setenv("PDS_NON_INTERACTIVE", "1", 1);
    NSString *result = [PDSCLIInputHelper promptForInput:@"Enter value"
                                           defaultValue:@"default123"];
    XCTAssertEqualObjects(result, @"default123",
                          @"Non-interactive mode should return the default value");
}

- (void)testInputHelperConfirmationReturnsDefaultWhenNonInteractive {
    setenv("PDS_NON_INTERACTIVE", "1", 1);
    BOOL result = [PDSCLIInputHelper promptForConfirmation:@"Confirm?" defaultYes:YES];
    XCTAssertTrue(result, @"Non-interactive should return defaultYes=YES");

    result = [PDSCLIInputHelper promptForConfirmation:@"Confirm?" defaultYes:NO];
    XCTAssertFalse(result, @"Non-interactive should return defaultYes=NO");
}

- (void)testInputHelperChoiceReturnsDefaultWhenNonInteractive {
    setenv("PDS_NON_INTERACTIVE", "1", 1);
    NSInteger idx = [PDSCLIInputHelper promptForChoice:@"Pick one"
                                              choices:@[@"A", @"B", @"C"]
                                         defaultIndex:1];
    XCTAssertEqual(idx, 1, @"Non-interactive should return the default index");
}

// MARK: - Priority 7: PDSCLIAccountManager utility methods

- (void)testAccountManagerDatabasePathForNilDataDir {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    ctx.dataDir = @"/tmp/test-pds-data";
    NSString *path = [PDSCLIAccountManager databasePathForContext:ctx];
    XCTAssertNotNil(path, @"Database path should be non-nil");
    XCTAssertTrue([path hasPrefix:@"/tmp/test-pds-data"],
                  @"Database path should be under the data directory");
}

- (void)testAccountManagerHostnameForContext {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    NSString *hostname = [PDSCLIAccountManager pdsHostnameForContext:ctx];
    XCTAssertNotNil(hostname, @"PDS hostname should have a default");
}

- (void)testAccountManagerServiceEndpointForContext {
    PDSCLICommandContext *ctx = [[PDSCLICommandContext alloc] init];
    NSString *endpoint = [PDSCLIAccountManager pdsServiceEndpointForContext:ctx];
    XCTAssertNotNil(endpoint, @"Service endpoint should have a default");
}

@end

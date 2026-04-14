#import <XCTest/XCTest.h>
#import "CLI/PDSCLIDispatcher.h"

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

@end

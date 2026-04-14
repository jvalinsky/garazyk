#import <XCTest/XCTest.h>
#import "PLC/DIDPLCResolver.h"

@interface DIDPLCResolverTests : XCTestCase
@end

@implementation DIDPLCResolverTests

- (void)testInvalidDIDRejection {
    DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:@"http://localhost:2582"];
    NSError *error = nil;
    NSDictionary *doc = [resolver resolveDID:@"did:web:example.com" error:&error];
    
    XCTAssertNil(doc);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, DIDPLCResolverErrorDomain);
    XCTAssertEqual(error.code, DIDPLCResolverErrorInvalidDID);
}

- (void)testResolverReturnsErrorOnTimeout {
    // Port 1 (should fail immediately or timeout depending on system)
    DIDPLCResolver *resolver = [[DIDPLCResolver alloc] initWithPlcUrl:@"http://localhost:1"];
    resolver.timeout = 0.5; // Very short timeout
    
    NSError *error = nil;
    NSDictionary *doc = [resolver resolveDID:@"did:plc:ragtjsm2j2vponprpuglwxpn" error:&error];
    
    XCTAssertNil(doc);
    XCTAssertNotNil(error);
}

@end

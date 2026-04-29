#import <XCTest/XCTest.h>
#import "TutorialCIDGenerator.h"

@interface TutorialCIDGeneratorTests : XCTestCase
@end

@implementation TutorialCIDGeneratorTests

- (void)testGenerateCIDForData {
    NSData *data = [@"Hello ATProto" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [TutorialCIDGenerator generateCIDForData:data];
    XCTAssertNotNil(cid, @"CID should not be nil");
    XCTAssertTrue(cid.length > 0, @"CID should not be empty");
}

- (void)testCIDStartsWithBafyrei {
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [TutorialCIDGenerator generateCIDForData:data];
    XCTAssertTrue([cid hasPrefix:@"bafyrei"], @"CIDv1 with dag-cbor should start with 'bafyrei'");
}

- (void)testCIDDeterministic {
    NSData *data = [@"same content" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid1 = [TutorialCIDGenerator generateCIDForData:data];
    NSString *cid2 = [TutorialCIDGenerator generateCIDForData:data];
    XCTAssertEqualObjects(cid1, cid2, @"Same content should produce same CID");
}

- (void)testDifferentContentDifferentCID {
    NSData *data1 = [@"content A" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data2 = [@"content B" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid1 = [TutorialCIDGenerator generateCIDForData:data1];
    NSString *cid2 = [TutorialCIDGenerator generateCIDForData:data2];
    XCTAssertNotEqualObjects(cid1, cid2, @"Different content should produce different CIDs");
}

- (void)testGenerateCIDForJSON {
    NSDictionary *json = @{@"text": @"Hello from JSON!", @"createdAt": @"2024-01-01T00:00:00Z"};
    NSString *cid = [TutorialCIDGenerator generateCIDForJSON:json];
    XCTAssertNotNil(cid);
    XCTAssertTrue([cid hasPrefix:@"bafyrei"], @"JSON CID should also start with bafyrei");
}

- (void)testCIDForJSONDeterministic {
    NSDictionary *json = @{@"$type": @"app.bsky.feed.post", @"text": @"Test"};
    NSString *cid1 = [TutorialCIDGenerator generateCIDForJSON:json];
    NSString *cid2 = [TutorialCIDGenerator generateCIDForJSON:json];
    XCTAssertEqualObjects(cid1, cid2, @"Same JSON should produce same CID");
}

- (void)testCIDLength {
    NSData *data = [@"test data" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *cid = [TutorialCIDGenerator generateCIDForData:data];
    XCTAssertTrue(cid.length >= 59, @"CID should be at least 59 base32 characters");
}

@end

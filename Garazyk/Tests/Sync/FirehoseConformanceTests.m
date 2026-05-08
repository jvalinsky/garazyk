#import <XCTest/XCTest.h>
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Core/ATProtoDagCBOR.h"

@interface FirehoseConformanceTests : XCTestCase
@property (nonatomic, strong) EventFormatter *formatter;
@end

@implementation FirehoseConformanceTests

- (void)setUp {
    [super setUp];
    self.formatter = [[EventFormatter alloc] init];
}

- (void)testCommitEventRemovesRecordCBORFromOps {
    // Create a dummy commit event with recordCBOR in ops
    NSData *dummyRecordData = [@"{\"text\":\"hello\"}" dataUsingEncoding:NSUTF8StringEncoding];
    
    // Valid CID using SHA-256 (required for CBOR tag 42 round-trip)
    CID *dummyCID = [CID sha256:[@"dummy" dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSDictionary *opWithCBOR = @{
        @"action": @"create",
        @"path": @"app.bsky.feed.post/rkey",
        @"cid": dummyCID ?: [NSNull null],
        @"recordCBOR": dummyRecordData
    };
    
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 123;
    event.repo = @"did:plc:test";
    event.commit = dummyCID; // Required
    event.rev = @"3k3k3k3k3k3k3"; // Required
    event.ops = @[opWithCBOR];
    event.time = @"2024-01-01T00:00:00Z";
    event.blocks = [NSData data]; // Empty CAR for this test
    
    NSError *error = nil;
    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    XCTAssertNotNil(encoded, @"Encoding failed: %@", error);
    XCTAssertNil(error);
    
    // Decode and verify payload
    // XRPC frame format: [Header (CBOR), Payload (CBOR)] concatenated
    // We need to decode the initial object (header) then the second (payload)
    
    NSUInteger index = 0;
    // Helper method not exposed in header, so we rely on public decodeEventFromData if we can, 
    // or just assume standard CBOR sequence if I had a decoder handy.
    // EventFormatter DOES have decodeEventFromData:op:msgType:error:
    
    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decodedPayload = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];
    
    XCTAssertNotNil(decodedPayload, @"Decoding failed: %@", error);
    XCTAssertEqual(op, 1);
    XCTAssertEqualObjects(msgType, @"#commit");
    
    NSArray *ops = decodedPayload[@"ops"];
    XCTAssertEqual(ops.count, 1);
    NSDictionary *decodedOp = ops.firstObject;
    
    // This assertion should FAIL currently because we haven't stripped it yet
    XCTAssertNil(decodedOp[@"recordCBOR"], @"recordCBOR should be stripped from ops in the event payload");
    XCTAssertEqualObjects(decodedOp[@"action"], @"create");
}

- (void)testEventSizeConstraintFailsEncoding {
    // Create a huge event
    NSMutableData *hugeData = [NSMutableData dataWithLength:1024 * 1024 + 100]; // > 1MB
    
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.seq = 124;
    event.repo = @"did:plc:test";
    event.commit = [CID sha256:[@"size-test-cid" dataUsingEncoding:NSUTF8StringEncoding]];
    event.rev = @"3k3k3k3k3k3k3";
    event.blocks = hugeData;
    event.ops = @[];
    event.time = @"2024-01-01T00:00:00Z";
    
    NSError *error = nil;
    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    
    // Logic not implemented yet, so this might pass (fail to error) or fail generally
    // Ideally we want it to return error or contain tooBig=true?
    // Note: tooBig=true is deprecated but "blocks" can be omitted if too big?
    // Actually current spec says max frame size is 1MB.
    
    // For now, let's just see if we enforce anything.
    // If not, we assert strict limit.
    
    if (encoded == nil && error != nil) {
        // Passed: Encoding should fail
        NSLog(@"Encoding failed as expected for huge event: %@", error);
    } else {
        XCTFail(@"Encoded huge event should have failed, but got %lu bytes", (unsigned long)encoded.length);
    }
}

@end

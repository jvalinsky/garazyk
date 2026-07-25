// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Core/ATProtoDagCBOR.h"

@interface EventFormatterTests : XCTestCase
@property (nonatomic, strong) EventFormatter *formatter;
@end

@implementation EventFormatterTests

- (void)setUp {
    [super setUp];
    self.formatter = [[EventFormatter alloc] init];
}

- (void)tearDown {
    self.formatter = nil;
    [super tearDown];
}

- (void)testEncodeCommitEvent {
    NSError *error = nil;
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:abc123";
    // Create a valid CID using SHA-256 (required for CBOR tag 42 round-trip)
    event.commit = [CID sha256:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    event.ops = @[@{@"action": @"create", @"path": @"/app.bsky.feed.post/123"}];
    event.blobs = @[];  // Empty array for now
    
    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testEncodeCommitEventWithoutOptionalFields {
    NSError *error = nil;
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:abc123";
    event.commit = [CID sha256:[@"test2" dataUsingEncoding:NSUTF8StringEncoding]];
    event.rev = @"3k3k3k3k3k3k3";
    event.time = @"2024-01-01T00:00:00Z";
    event.ops = @[];
    event.blobs = @[];
    
    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertEqualObjects(msgType, @"#commit");
    XCTAssertNotNil(decoded[@"blocks"]);
    XCTAssertEqualObjects(decoded[@"since"], [NSNull null]);
}

- (void)testEncodeIdentityEvent {
    NSError *error = nil;
    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.seq = 17;
    event.did = @"did:plc:abc123";
    event.time = @"2024-01-01T00:00:00Z";
    
    NSData *encoded = [self.formatter encodeIdentityEvent:event error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testDecodeSyncEvent {
    NSError *error = nil;
    FirehoseSyncEvent *event = [[FirehoseSyncEvent alloc] init];
    event.seq = 42;
    event.did = @"did:plc:sync123";
    event.rev = @"3k3k3k3k3k3k3";
    event.time = @"2024-01-01T00:00:00Z";
    event.blocks = [@"car-bytes" dataUsingEncoding:NSUTF8StringEncoding];

    NSData *encoded = [self.formatter encodeSyncEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqual(op, 1);
    XCTAssertEqualObjects(msgType, @"#sync");
    XCTAssertEqualObjects(decoded[@"seq"], @42);
    XCTAssertEqualObjects(decoded[@"did"], @"did:plc:sync123");
    XCTAssertEqualObjects(decoded[@"rev"], @"3k3k3k3k3k3k3");
    XCTAssertEqualObjects(decoded[@"time"], @"2024-01-01T00:00:00Z");
    XCTAssertEqualObjects(decoded[@"blocks"], event.blocks);
}

- (void)testEncodeErrorEvent {
    NSError *error = nil;
    FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
    event.message = @"Something went wrong";
    
    NSData *encoded = [self.formatter encodeErrorEvent:event error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testDecodeCommitEvent {
    NSError *error = nil;
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:abc123";
    event.commit = [CID sha256:[@"test3" dataUsingEncoding:NSUTF8StringEncoding]];
    event.ops = @[@{@"action": @"create"}];
    event.blobs = @[];

    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqual(op, 1);
    XCTAssertEqualObjects(msgType, @"#commit");
    XCTAssertEqualObjects(decoded[@"repo"], @"did:plc:abc123");
    CID *originalCID = event.commit;
    CID *decodedCID = decoded[@"commit"];
    XCTAssertEqualObjects(decodedCID, originalCID, @"Decoded CID should match original CID");
}

- (void)testDecodeIdentityEvent {
    NSError *error = nil;
    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.seq = 11;
    event.did = @"did:plc:abc123";
    event.time = @"2024-01-01T00:00:00Z";
    event.handle = @"handle.bsky.social";

    NSData *encoded = [self.formatter encodeIdentityEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqual(op, 1);
    XCTAssertEqualObjects(msgType, @"#identity");
    XCTAssertEqualObjects(decoded[@"seq"], @11);
    XCTAssertEqualObjects(decoded[@"did"], @"did:plc:abc123");
    XCTAssertEqualObjects(decoded[@"time"], @"2024-01-01T00:00:00Z");
    XCTAssertEqualObjects(decoded[@"handle"], @"handle.bsky.social");
}

- (void)testDecodeErrorEvent {
    NSError *error = nil;
    FirehoseErrorEvent *event = [[FirehoseErrorEvent alloc] init];
    event.message = @"Test error message";

    NSData *encoded = [self.formatter encodeErrorEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqual(op, -1);
    XCTAssertEqualObjects(msgType, @"#error");
}

- (void)testDecodeAccountEvent {
    NSError *error = nil;
    FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
    event.seq = 22;
    event.did = @"did:plc:abc123";
    event.active = NO;
    event.status = @"takendown";
    event.time = @"2024-01-01T00:00:00Z";

    NSData *encoded = [self.formatter encodeAccountEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqual(op, 1);
    XCTAssertEqualObjects(msgType, @"#account");
    XCTAssertEqualObjects(decoded[@"seq"], @22);
    XCTAssertEqualObjects(decoded[@"did"], @"did:plc:abc123");
    XCTAssertEqualObjects(decoded[@"time"], @"2024-01-01T00:00:00Z");
    XCTAssertEqualObjects(decoded[@"status"], @"takendown");
}

- (void)testDecodeInfoEvent {
    NSError *error = nil;
    FirehoseInfoEvent *event = [[FirehoseInfoEvent alloc] init];
    event.kind = @"OutdatedCursor";
    event.message = @"Unable to retrieve repository state";

    NSData *encoded = [self.formatter encodeInfoEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqual(op, 1);
    XCTAssertEqualObjects(msgType, @"#info");
    XCTAssertEqualObjects(decoded[@"name"], @"OutdatedCursor");
    XCTAssertEqualObjects(decoded[@"message"], @"Unable to retrieve repository state");
}

- (void)testEventFormatterErrorDomain {
    XCTAssertEqualObjects(EventFormatterErrorDomain, @"com.atproto.pds.eventformatter");
    XCTAssertEqual(EventFormatterErrorCodeEncodingFailed, 5000);
    XCTAssertEqual(EventFormatterErrorCodeDecodingFailed, 5001);
}

- (void)testDecodeRejectsOversizedFrame {
    NSMutableData *data = [NSMutableData dataWithLength:(1024 * 1024) + 1];
    NSError *error = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:data
                                                             op:nil
                                                        msgType:nil
                                                           error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, EventFormatterErrorCodeDecodingFailed);
}

- (void)testDecodeRejectsHeaderWithUnboundedMapLength {
    const uint8_t bytes[] = {0xBA, 0x00, 0x00, 0x13, 0x89};
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    NSError *error = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:data
                                                             op:nil
                                                        msgType:nil
                                                           error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
}

- (void)testDecodeRejectsExcessiveHeaderNesting {
    NSMutableData *data = [NSMutableData data];
    const uint8_t mapStart[] = {0xA1, 0x61, 0x78};
    [data appendBytes:mapStart length:sizeof(mapStart)];
    uint8_t arrayStart = 0x81;
    for (NSUInteger index = 0; index < 34; index++) {
        [data appendBytes:&arrayStart length:1];
    }
    uint8_t nullValue = 0xF6;
    [data appendBytes:&nullValue length:1];

    NSError *error = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:data
                                                             op:nil
                                                        msgType:nil
                                                           error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
}

- (void)testDecodeRejectsUnboundedPayloadContainer {
    NSError *error = nil;
    NSData *header = [ATProtoDagCBOR encodeObject:@{
        @"op": @1,
        @"t": @"#commit",
    } error:&error];
    XCTAssertNotNil(header);

    NSMutableData *frame = [header mutableCopy];
    const uint8_t oversizedArray[] = {0x9A, 0x00, 0x00, 0x13, 0x89};
    [frame appendBytes:oversizedArray length:sizeof(oversizedArray)];

    NSDictionary *decoded = [self.formatter decodeEventFromData:frame
                                                             op:nil
                                                        msgType:nil
                                                           error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
}

- (void)testDecodeRejectsNonMapPayload {
    NSError *error = nil;
    NSData *header = [ATProtoDagCBOR encodeObject:@{
        @"op": @1,
        @"t": @"#commit",
    } error:&error];
    NSMutableData *frame = [header mutableCopy];
    uint8_t emptyArray = 0x80;
    [frame appendBytes:&emptyArray length:1];

    NSDictionary *decoded = [self.formatter decodeEventFromData:frame
                                                             op:nil
                                                        msgType:nil
                                                           error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
}

#pragma mark - Seq Round-Trip Tests

- (void)testSyncEventSeqRoundTrip {
    NSError *error = nil;
    FirehoseSyncEvent *event = [[FirehoseSyncEvent alloc] init];
    event.seq = 42;
    event.did = @"did:plc:seqroundtrip";
    event.rev = @"3kseqrt";
    event.time = @"2024-01-01T00:00:00Z";
    event.blocks = [NSData data];

    NSData *encoded = [self.formatter encodeSyncEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(msgType, @"#sync");
    XCTAssertEqualObjects(decoded[@"seq"], @42, @"seq should survive round-trip");
}

- (void)testIdentityEventSeqRoundTrip {
    NSError *error = nil;
    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.seq = 99;
    event.did = @"did:plc:identityseqrt";
    event.time = @"2024-01-01T00:00:00Z";
    event.handle = @"handle.bsky.social";

    NSData *encoded = [self.formatter encodeIdentityEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(msgType, @"#identity");
    XCTAssertEqualObjects(decoded[@"seq"], @99, @"seq should survive round-trip");
}

- (void)testAccountEventSeqRoundTrip {
    NSError *error = nil;
    FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
    event.seq = 777;
    event.did = @"did:plc:accountseqrt";
    event.active = NO;
    event.status = @"deactivated";
    event.time = @"2024-01-01T00:00:00Z";

    NSData *encoded = [self.formatter encodeAccountEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(msgType, @"#account");
    XCTAssertEqualObjects(decoded[@"seq"], @777, @"seq should survive round-trip");
}

- (void)testOpsCIDRoundTrip {
    // Verify that CID objects in ops survive encode→decode round-trip
    NSError *error = nil;
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:roundtrip";
    event.rev = @"3kroundtrip";
    event.time = @"2024-01-01T00:00:00Z";
    event.commit = [CID sha256:[@"roundtrip-test" dataUsingEncoding:NSUTF8StringEncoding]];

    // Create a CID for the op's record
    CID *recordCID = [CID sha256:[@"record-cid-test" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertNotNil(recordCID, @"Precondition: record CID must be created");

    event.ops = @[@{
        @"action": @"create",
        @"path": @"app.bsky.feed.post/3kabc123",
        @"cid": recordCID
    }];
    event.blobs = @[];

    // Encode
    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    XCTAssertNotNil(encoded, @"Encoding should succeed");
    XCTAssertNil(error, @"No encoding error expected");

    // Decode
    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];
    XCTAssertNotNil(decoded, @"Decoding should succeed");
    XCTAssertNil(error, @"No decoding error expected: %@", error.localizedDescription);
    XCTAssertEqualObjects(msgType, @"#commit");

    // Verify ops survived round-trip
    NSArray *decodedOps = decoded[@"ops"];
    XCTAssertEqual(decodedOps.count, 1U, @"Should have 1 op");
    NSDictionary *decodedOp = decodedOps.firstObject;
    XCTAssertEqualObjects(decodedOp[@"action"], @"create", @"Action should survive round-trip");
    XCTAssertEqualObjects(decodedOp[@"path"], @"app.bsky.feed.post/3kabc123", @"Path with rkey should survive round-trip");

    // Verify CID survived round-trip
    id decodedCIDValue = decodedOp[@"cid"];
    XCTAssertTrue([decodedCIDValue isKindOfClass:[CID class]], @"cid should be a CID object, got %@", NSStringFromClass([decodedCIDValue class]));
    if ([decodedCIDValue isKindOfClass:[CID class]]) {
        CID *decodedCID = (CID *)decodedCIDValue;
        XCTAssertEqualObjects(decodedCID.stringValue, recordCID.stringValue, @"CID string should match after round-trip");
    }
}

- (void)testOpsCIDNullRoundTrip {
    // Verify that NSNull cid in ops (for delete ops) survives round-trip
    NSError *error = nil;
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:deletetest";
    event.rev = @"3kdeletetest";
    event.time = @"2024-01-01T00:00:00Z";
    event.commit = [CID sha256:[@"delete-test" dataUsingEncoding:NSUTF8StringEncoding]];

    event.ops = @[@{
        @"action": @"delete",
        @"path": @"app.bsky.feed.post/3kdel456",
        @"cid": [NSNull null]
    }];
    event.blobs = @[];

    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSDictionary *decoded = [self.formatter decodeEventFromData:encoded op:&op msgType:&msgType error:&error];
    XCTAssertNotNil(decoded);
    XCTAssertNil(error);

    NSArray *decodedOps = decoded[@"ops"];
    XCTAssertEqual(decodedOps.count, 1U);
    NSDictionary *decodedOp = decodedOps.firstObject;
    XCTAssertEqualObjects(decodedOp[@"action"], @"delete");
    XCTAssertEqualObjects(decodedOp[@"path"], @"app.bsky.feed.post/3kdel456");
    XCTAssertTrue([decodedOp[@"cid"] isKindOfClass:[NSNull class]], @"cid should be NSNull for delete ops");
}

@end

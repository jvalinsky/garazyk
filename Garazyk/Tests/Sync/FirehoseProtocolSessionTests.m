#import <XCTest/XCTest.h>
#import "Sync/Firehose/FirehoseProtocolSession.h"
#import "Sync/Relay/EventFormatter.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"

@interface FirehoseProtocolSessionTests : XCTestCase
@property (nonatomic, strong) EventFormatter *formatter;
@end

@implementation FirehoseProtocolSessionTests

- (void)setUp {
    [super setUp];
    self.formatter = [[EventFormatter alloc] init];
}

- (void)tearDown {
    self.formatter = nil;
    [super tearDown];
}

#pragma mark - Seq in CBOR payload (identity/account/sync — no CID decode issues)

- (void)testEncodeIdentityEventSetsSeqInPayload {
    FirehoseProtocolSession *session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:20];

    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.did = @"did:plc:identityseq";
    event.time = @"2024-01-01T00:00:00Z";

    NSData *encoded = [session encodeIdentityEvent:event];
    XCTAssertNotNil(encoded);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *error = nil;
    NSDictionary *payload = [self.formatter decodeEventFromData:encoded
                                                            op:&op
                                                       msgType:&msgType
                                                         error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(payload);
    XCTAssertEqualObjects(msgType, @"#identity");
    XCTAssertEqualObjects(payload[@"seq"], @21, @"seq should be 21 (startSeq 20 + 1)");
}

- (void)testEncodeAccountEventSetsSeqInPayload {
    FirehoseProtocolSession *session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:50];

    FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
    event.did = @"did:plc:accountseq";
    event.active = YES;
    event.time = @"2024-01-01T00:00:00Z";

    NSData *encoded = [session encodeAccountEvent:event];
    XCTAssertNotNil(encoded);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *error = nil;
    NSDictionary *payload = [self.formatter decodeEventFromData:encoded
                                                            op:&op
                                                       msgType:&msgType
                                                         error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(payload);
    XCTAssertEqualObjects(msgType, @"#account");
    XCTAssertEqualObjects(payload[@"seq"], @51, @"seq should be 51 (startSeq 50 + 1)");
}

- (void)testEncodeSyncEventSetsSeqInPayload {
    FirehoseProtocolSession *session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:100];

    FirehoseSyncEvent *event = [[FirehoseSyncEvent alloc] init];
    event.did = @"did:plc:syncseq";
    event.rev = @"3ksynctest";
    event.time = @"2024-01-01T00:00:00Z";
    event.blocks = [NSData data];

    NSData *encoded = [session encodeSyncEvent:event];
    XCTAssertNotNil(encoded);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *error = nil;
    NSDictionary *payload = [self.formatter decodeEventFromData:encoded
                                                            op:&op
                                                       msgType:&msgType
                                                         error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(payload);
    XCTAssertEqualObjects(msgType, @"#sync");
    XCTAssertEqualObjects(payload[@"seq"], @101, @"seq should be 101 (startSeq 100 + 1)");
}

#pragma mark - Commit event seq (check session.sequenceNumber, not CBOR decode)

- (void)testEncodeCommitEventIncrementsSequence {
    FirehoseProtocolSession *session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:10];

    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:testseq";
    NSData *digest = [@"seq-test" dataUsingEncoding:NSUTF8StringEncoding];
    event.commit = [CID cidWithDigest:digest codec:0x71];
    event.rev = @"3kseqtest";
    event.time = @"2024-01-01T00:00:00Z";
    event.ops = @[];
    event.blobs = @[];

    NSUInteger seqBefore = session.sequenceNumber;
    NSData *encoded = [session encodeCommitEvent:event];
    XCTAssertNotNil(encoded);
    XCTAssertEqual(session.sequenceNumber, seqBefore + 1,
                   @"encodeCommitEvent should increment sequence by 1");
    XCTAssertEqual(session.sequenceNumber, 11U,
                   @"seq should be 11 after encoding with startSeq 10");
}

#pragma mark - Monotonic sequence

- (void)testSequenceMonotonicallyIncreases {
    FirehoseProtocolSession *session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:0];

    // Encode an identity event (seq should be 1)
    FirehoseIdentityEvent *identity = [[FirehoseIdentityEvent alloc] init];
    identity.did = @"did:plc:mono1";
    identity.time = @"2024-01-01T00:00:00Z";
    NSData *data1 = [session encodeIdentityEvent:identity];
    XCTAssertNotNil(data1);

    // Encode an account event (seq should be 2)
    FirehoseAccountEvent *account = [[FirehoseAccountEvent alloc] init];
    account.did = @"did:plc:mono2";
    account.active = YES;
    account.time = @"2024-01-01T00:00:00Z";
    NSData *data2 = [session encodeAccountEvent:account];
    XCTAssertNotNil(data2);

    // Encode a sync event (seq should be 3)
    FirehoseSyncEvent *sync = [[FirehoseSyncEvent alloc] init];
    sync.did = @"did:plc:mono3";
    sync.rev = @"3kmono3";
    sync.time = @"2024-01-01T00:00:00Z";
    sync.blocks = [NSData data];
    NSData *data3 = [session encodeSyncEvent:sync];
    XCTAssertNotNil(data3);

    // Verify seq values
    NSError *error = nil;
    NSInteger op = 0;
    NSString *msgType = nil;

    NSDictionary *p1 = [self.formatter decodeEventFromData:data1 op:&op msgType:&msgType error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(p1[@"seq"], @1);

    NSDictionary *p2 = [self.formatter decodeEventFromData:data2 op:&op msgType:&msgType error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(p2[@"seq"], @2);

    NSDictionary *p3 = [self.formatter decodeEventFromData:data3 op:&op msgType:&msgType error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(p3[@"seq"], @3);
}

#pragma mark - Info events don't consume seq

- (void)testEncodeInfoEventDoesNotIncrementSequence {
    FirehoseProtocolSession *session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:5];

    // Encode an info event
    FirehoseInfoEvent *info = [[FirehoseInfoEvent alloc] init];
    info.kind = @"OutdatedCursor";
    info.message = @"test";

    NSData *infoData = [session encodeInfoEvent:info];
    XCTAssertNotNil(infoData);

    // Sequence should NOT have incremented
    XCTAssertEqual(session.sequenceNumber, 5U,
                   @"Info events should not consume a sequence number");

    // Now encode an identity event — seq should be 6 (5 + 1)
    FirehoseIdentityEvent *identity = [[FirehoseIdentityEvent alloc] init];
    identity.did = @"did:plc:afterinfo";
    identity.time = @"2024-01-01T00:00:00Z";

    NSData *identityData = [session encodeIdentityEvent:identity];
    XCTAssertNotNil(identityData);

    NSInteger op = 0;
    NSString *msgType = nil;
    NSError *error = nil;
    NSDictionary *payload = [self.formatter decodeEventFromData:identityData
                                                            op:&op
                                                       msgType:&msgType
                                                         error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(payload[@"seq"], @6,
                          @"Identity after info should have seq=6, not seq=7 (no double-increment)");
}

#pragma mark - nextSequenceNumber

- (void)testNextSequenceNumberIncrements {
    FirehoseProtocolSession *session = [[FirehoseProtocolSession alloc] initWithSequenceNumber:0];

    NSUInteger seq1 = [session nextSequenceNumber];
    NSUInteger seq2 = [session nextSequenceNumber];
    NSUInteger seq3 = [session nextSequenceNumber];

    XCTAssertEqual(seq1, 1U);
    XCTAssertEqual(seq2, 2U);
    XCTAssertEqual(seq3, 3U);
    XCTAssertEqual(session.sequenceNumber, 3U);
}

@end

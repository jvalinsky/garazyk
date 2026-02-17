#import <XCTest/XCTest.h>
#import "Sync/EventFormatter.h"
#import "Sync/Firehose.h"
#import "Core/CID.h"

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
    // Create a dummy CID for testing
    NSData *digest = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    event.commit = [CID cidWithDigest:digest codec:0x71];
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
    NSData *digest = [@"test2" dataUsingEncoding:NSUTF8StringEncoding];
    event.commit = [CID cidWithDigest:digest codec:0x71];
    event.ops = @[];
    event.blobs = @[];
    
    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testEncodeIdentityEvent {
    NSError *error = nil;
    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.did = @"did:plc:abc123";
    
    NSData *encoded = [self.formatter encodeIdentityEvent:event error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
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
    NSData *digest = [@"test3" dataUsingEncoding:NSUTF8StringEncoding];
    event.commit = [CID cidWithDigest:digest codec:0x71];
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
    // XCTAssertEqualObjects(decoded[@"commit"], ...);  // TODO: verify CID encoding
}

- (void)testDecodeIdentityEvent {
    NSError *error = nil;
    FirehoseIdentityEvent *event = [[FirehoseIdentityEvent alloc] init];
    event.did = @"did:plc:abc123";
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
    XCTAssertEqualObjects(decoded[@"did"], @"did:plc:abc123");
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
    event.did = @"did:plc:abc123";
    event.active = NO;
    event.status = @"takendown";

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
    XCTAssertEqualObjects(decoded[@"did"], @"did:plc:abc123");
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
    XCTAssertEqualObjects(decoded[@"info"], @"OutdatedCursor");
    XCTAssertEqualObjects(decoded[@"message"], @"Unable to retrieve repository state");
}

- (void)testEventFormatterErrorDomain {
    XCTAssertEqualObjects(EventFormatterErrorDomain, @"com.atproto.pds.eventformatter");
    XCTAssertEqual(EventFormatterErrorCodeEncodingFailed, 5000);
    XCTAssertEqual(EventFormatterErrorCodeDecodingFailed, 5001);
}

@end

#import <XCTest/XCTest.h>
#import "Sync/EventFormatter.h"
#import "Sync/Firehose.h"

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

- (void)testCBORStringEncoding {
    NSError *error = nil;
    NSData *encoded = [self.formatter encodeCBORObject:@"hello" error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
    XCTAssertGreaterThan(encoded.length, 0);
}

- (void)testCBORStringRoundtrip {
    NSError *error = nil;
    NSString *original = @"test string with special chars: @#$%";
    NSData *encoded = [self.formatter encodeCBORObject:original error:&error];
    XCTAssertNotNil(encoded);
    
    id decoded = [self.formatter decodeCBORData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(decoded, original);
}

- (void)testCBORNumberEncoding {
    NSError *error = nil;
    
    NSData *zero = [self.formatter encodeCBORObject:@(0) error:&error];
    XCTAssertNotNil(zero);
    
    NSData *small = [self.formatter encodeCBORObject:@(23) error:&error];
    XCTAssertNotNil(small);
    
    NSData *medium = [self.formatter encodeCBORObject:@(255) error:&error];
    XCTAssertNotNil(medium);
    
    NSData *large = [self.formatter encodeCBORObject:@(1000000) error:&error];
    XCTAssertNotNil(large);
}

- (void)testCBORNumberRoundtrip {
    NSError *error = nil;
    NSArray *numbers = @[@(0), @(1), @(23), @(24), @(255), @(256), @(65535), @(1000000), @(-1), @(-100)];
    
    for (NSNumber *num in numbers) {
        NSData *encoded = [self.formatter encodeCBORObject:num error:&error];
        XCTAssertNotNil(encoded);
        
        id decoded = [self.formatter decodeCBORData:encoded error:&error];
        XCTAssertNil(error);
        XCTAssertEqualObjects(decoded, num);
    }
}

- (void)testCBORBooleanEncoding {
    NSError *error = nil;
    
    NSData *trueData = [self.formatter encodeCBORObject:@YES error:&error];
    XCTAssertNotNil(trueData);
    XCTAssertEqual(trueData.length, 1);
    XCTAssertEqual(((uint8_t *)trueData.bytes)[0], 0xF5);
    
    NSData *falseData = [self.formatter encodeCBORObject:@NO error:&error];
    XCTAssertNotNil(falseData);
    XCTAssertEqual(falseData.length, 1);
    XCTAssertEqual(((uint8_t *)falseData.bytes)[0], 0xF4);
}

- (void)testCBORBooleanRoundtrip {
    NSError *error = nil;
    
    NSData *encoded = [self.formatter encodeCBORObject:@YES error:&error];
    id decoded = [self.formatter decodeCBORData:encoded error:&error];
    XCTAssertEqualObjects(decoded, @YES);
    
    encoded = [self.formatter encodeCBORObject:@NO error:&error];
    decoded = [self.formatter decodeCBORData:encoded error:&error];
    XCTAssertEqualObjects(decoded, @NO);
}

- (void)testCBORNullEncoding {
    NSError *error = nil;
    NSData *encoded = [self.formatter encodeCBORObject:[NSNull null] error:&error];
    XCTAssertNotNil(encoded);
    XCTAssertEqual(encoded.length, 1);
    XCTAssertEqual(((uint8_t *)encoded.bytes)[0], 0xF6);
}

- (void)testCBORArrayEncoding {
    NSError *error = nil;
    NSArray *array = @[@(1), @(2), @(3)];
    NSData *encoded = [self.formatter encodeCBORObject:array error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testCBORArrayRoundtrip {
    NSError *error = nil;
    NSArray *original = @[@"a", @"b", @"c", @(1), @(2)];
    NSData *encoded = [self.formatter encodeCBORObject:original error:&error];
    XCTAssertNotNil(encoded);
    
    id decoded = [self.formatter decodeCBORData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(decoded, original);
}

- (void)testCBORDictionaryEncoding {
    NSError *error = nil;
    NSDictionary *dict = @{@"key": @"value", @"number": @(42)};
    NSData *encoded = [self.formatter encodeCBORObject:dict error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testCBORDictionaryRoundtrip {
    NSError *error = nil;
    NSDictionary *original = @{@"name": @"test", @"value": @(100), @"nested": @{@"inner": @"data"}};
    NSData *encoded = [self.formatter encodeCBORObject:original error:&error];
    XCTAssertNotNil(encoded);
    
    id decoded = [self.formatter decodeCBORData:encoded error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(decoded, original);
}

- (void)testCBORBytesEncoding {
    NSError *error = nil;
    NSData *bytes = [@"\x01\x02\x03\x04" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *encoded = [self.formatter encodeCBORObject:bytes error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testCBOREmptyData {
    NSError *error = nil;
    NSData *encoded = [self.formatter encodeCBORObject:@[] error:&error];
    XCTAssertNotNil(encoded);
    
    id decoded = [self.formatter decodeCBORData:encoded error:&error];
    XCTAssertEqualObjects(decoded, @[]);
}

- (void)testEncodeCommitEvent {
    NSError *error = nil;
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:abc123";
    event.commit = @"bafyre...";
    event.ops = @[@{@"action": @"create", @"path": @"/app.bsky.feed.post/123"}];
    event.blobs = @[@"bafkqi..."];
    
    NSData *encoded = [self.formatter encodeCommitEvent:event error:&error];
    
    XCTAssertNotNil(encoded);
    XCTAssertNil(error);
}

- (void)testEncodeCommitEventWithoutOptionalFields {
    NSError *error = nil;
    FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:abc123";
    event.commit = @"bafyre...";
    event.ops = @[];
    
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
    event.commit = @"bafyre...";
    event.ops = @[@{@"action": @"create"}];

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
    XCTAssertEqualObjects(decoded[@"commit"], @"bafyre...");
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

- (void)testDecodeInvalidCBOR {
    NSError *error = nil;
    NSData *invalidData = [NSData dataWithBytes:"\xFF" length:1];
    
    id decoded = [self.formatter decodeCBORData:invalidData error:&error];
    XCTAssertNil(decoded);
    XCTAssertNotNil(error);
}

- (void)testDecodeEmptyData {
    NSError *error = nil;
    NSData *emptyData = [NSData data];
    
    id decoded = [self.formatter decodeCBORData:emptyData error:&error];
    XCTAssertNil(decoded);
}

- (void)testCBORNestedStructure {
    NSError *error = nil;
    NSDictionary *original = @{
        @"repo": @"did:plc:abc",
        @"commit": @"bafyre...",
        @"ops": @[
            @{@"action": @"create", @"path": @"/app.bsky.feed.post/1", @"record": @{@"text": @"hello"}},
            @{@"action": @"delete", @"path": @"/app.bsky.feed.post/2"}
        ]
    };
    
    NSData *encoded = [self.formatter encodeCBORObject:original error:&error];
    XCTAssertNotNil(encoded);
    
    id decoded = [self.formatter decodeCBORData:encoded error:&error];
    XCTAssertEqualObjects(decoded, original);
}

- (void)testEventFormatterErrorDomain {
    XCTAssertEqualObjects(EventFormatterErrorDomain, @"com.atproto.pds.eventformatter");
    XCTAssertEqual(EventFormatterErrorCodeEncodingFailed, 5000);
    XCTAssertEqual(EventFormatterErrorCodeDecodingFailed, 5001);
}

@end

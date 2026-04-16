#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketConnection.h"
#import "Sync/WebSocket/WebSocketCodec.h"

@interface MockWebSocketDelegate2 : NSObject <WebSocketConnectionDelegate>
@property (nonatomic, strong) NSMutableArray<NSData *> *messages;
@property (nonatomic, strong) NSMutableArray<NSString *> *texts;
@property (nonatomic, assign) NSInteger lastCloseCode;
@property (nonatomic, strong) NSString *lastCloseReason;
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic, strong) XCTestExpectation *expectation;
@end

@implementation MockWebSocketDelegate2
- (instancetype)init {
    self = [super init];
    if (self) {
        _messages = [NSMutableArray array];
        _texts = [NSMutableArray array];
        _lastCloseCode = -1;
    }
    return self;
}
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveMessage:(NSData *)data {
    [self.messages addObject:data];
    if (self.expectation) [self.expectation fulfill];
}
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveText:(NSString *)text {
    [self.texts addObject:text];
    if (self.expectation) [self.expectation fulfill];
}
- (void)webSocketConnection:(WebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason {
    self.lastCloseCode = code;
    self.lastCloseReason = reason;
    if (self.expectation) [self.expectation fulfill];
}
- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error {
    self.lastError = error;
    if (self.expectation) [self.expectation fulfill];
}
@end

@interface WebSocketConnection (Testing2)
@property (nonatomic, assign, readwrite) WebSocketConnectionState state;
@property (nonatomic, strong) NSMutableData *readBuffer;
@property (nonatomic, strong) WebSocketCodec *codec;
- (void)handleReceivedData:(NSData *)data;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;
- (void)sendPong:(NSData *)payload;
@end

@interface WebSocketFrameCharacterizationTests : XCTestCase
@property (nonatomic, strong) WebSocketConnection *connection;
@property (nonatomic, strong) MockWebSocketDelegate2 *delegate;
@end

@implementation WebSocketFrameCharacterizationTests

- (void)setUp {
    [super setUp];
    self.connection = [[WebSocketConnection alloc] init];
    self.delegate = [[MockWebSocketDelegate2 alloc] init];
    self.connection.delegate = self.delegate;
    self.connection.state = WebSocketConnectionStateConnected;
}

- (void)tearDown {
    self.connection = nil;
    self.delegate = nil;
    [super tearDown];
}

// Helper to wrap waiting since the connection dispatches to main queue
- (void)waitForMainQueue {
    XCTestExpectation *exp = [self expectationWithDescription:@"Wait for main queue"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectations:@[exp] timeout:1.0];
}

- (void)testFragmentedFramesMatchesFirstObject {
    // Current WebSocketConnection doesn't fully support FIN=0 continuation frame reassembly in the parser itself.
    // Let's see what the current behavior actually is.
    // ACTUALLY, looking at handleReceivedData: it seems to dispatch every frame it sees directly.
    // We will just feed it two text frames and see what happens (since current code doesn't do reassembly).
    // Fin=0, Opcode=1 (Text), Len=2 -> "He"
    // Fin=1, Opcode=0 (Cont), Len=3 -> "llo"
    uint8_t frame1[] = {0x01, 0x02, 'H', 'e'};
    uint8_t frame2[] = {0x80, 0x03, 'l', 'l', 'o'};
    
    [self.connection handleReceivedData:[NSData dataWithBytes:frame1 length:sizeof(frame1)]];
    [self.connection handleReceivedData:[NSData dataWithBytes:frame2 length:sizeof(frame2)]];
    
    [self waitForMainQueue];
    
    // The current code correctly handles reassembly.
    XCTAssertEqual(self.delegate.texts.count, 1);
    XCTAssertEqualObjects(self.delegate.texts.firstObject, @"Hello");
}

- (void)testMaskedClientServerFrameMatchesLastObject {
    uint8_t frameBytes[] = {
        0x81, 0x85, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x9F, 0x4D, 0x51, 0x58
    };
    [self.connection handleReceivedData:[NSData dataWithBytes:frameBytes length:sizeof(frameBytes)]];
    [self waitForMainQueue];
    XCTAssertEqualObjects(self.delegate.texts.lastObject, @"Hello");
}

- (void)testConnectionReadyStateEqual {
    // Current behavior: opcode 9 is PING.
    uint8_t pingFrame[] = {0x89, 0x04, 'p','i','n','g'};
    [self.connection handleReceivedData:[NSData dataWithBytes:pingFrame length:sizeof(pingFrame)]];
    // Connection calls sendPong, but we didn't mock connection. Let's just ensure it doesn't crash.
    XCTAssertEqual(self.connection.state, WebSocketConnectionStateConnected, @"connection should remain open");
    [self waitForMainQueue];
}

- (void)testCloseFrameWithCodeAndReason {
    // Close code 1000 (0x03E8), reason "OK"
    uint8_t frame[] = {0x88, 0x04, 0x03, 0xE8, 'O', 'K'};
    [self.connection handleReceivedData:[NSData dataWithBytes:frame length:sizeof(frame)]];
    [self waitForMainQueue];
    // Wait for the close dispatch. It dispatches after 5s or state change. But wait, handleCloseFrame calls closeWithCode:reason:.
    // This transitions to Closing and dispatches after 5s. Let's just check the property or wait.
    XCTAssertEqual(self.connection.closeCode, 1000);
    XCTAssertEqualObjects(self.connection.closeReason, @"OK");
}

- (void)testCloseFrameEmptyPayload {
    uint8_t frame[] = {0x88, 0x00};
    [self.connection handleReceivedData:[NSData dataWithBytes:frame length:sizeof(frame)]];
    [self waitForMainQueue];
    XCTAssertEqual(self.connection.closeCode, 0);
    XCTAssertEqualObjects(self.connection.closeReason, @"");
}

- (void)testOversizedFrameRejectionClosesConnection {
    // frame > 16MB. 
    // Opcode=2, Len=127, 8-byte length = 17MB
    uint8_t frame[] = {0x82, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x01, 0x10, 0x00, 0x00};
    [self.connection handleReceivedData:[NSData dataWithBytes:frame length:sizeof(frame)]];
    [self waitForMainQueue];
    XCTAssertEqual(self.connection.closeCode, 1009);
    XCTAssertEqualObjects(self.connection.closeReason, @"Frame too large");
}

- (void)testBinaryFrameBoundaries {
    // 0 bytes
    uint8_t frame0[] = {0x82, 0x00};
    [self.connection handleReceivedData:[NSData dataWithBytes:frame0 length:sizeof(frame0)]];
    [self waitForMainQueue];
    XCTAssertEqual(self.delegate.messages.lastObject.length, 0);
    
    // 125 bytes
    NSMutableData *f125 = [NSMutableData data];
    uint8_t h125[] = {0x82, 125};
    [f125 appendBytes:h125 length:2];
    [f125 appendData:[NSMutableData dataWithLength:125]];
    [self.connection handleReceivedData:f125];
    [self waitForMainQueue];
    XCTAssertEqual(self.delegate.messages.lastObject.length, 125);
    
    // 126 bytes
    NSMutableData *f126 = [NSMutableData data];
    uint8_t h126[] = {0x82, 126, 0x00, 126};
    [f126 appendBytes:h126 length:4];
    [f126 appendData:[NSMutableData dataWithLength:126]];
    [self.connection handleReceivedData:f126];
    [self waitForMainQueue];
    XCTAssertEqual(self.delegate.messages.lastObject.length, 126);
    
    // 127 bytes
    NSMutableData *f127 = [NSMutableData data];
    uint8_t h127[] = {0x82, 126, 0x00, 127};
    [f127 appendBytes:h127 length:4];
    [f127 appendData:[NSMutableData dataWithLength:127]];
    [self.connection handleReceivedData:f127];
    [self waitForMainQueue];
    XCTAssertEqual(self.delegate.messages.lastObject.length, 127);
}

- (void)testPartialFrameDeliveryMatchesLastObject {
    uint8_t frameBytes[] = {
        0x81, 0x85, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x9F, 0x4D, 0x51, 0x58
    };
    for (int i=0; i<sizeof(frameBytes); i++) {
        [self.connection handleReceivedData:[NSData dataWithBytes:&frameBytes[i] length:1]];
    }
    [self waitForMainQueue];
    XCTAssertEqualObjects(self.delegate.texts.lastObject, @"Hello");
}

@end

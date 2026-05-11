// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/WebSocket/WebSocketConnection.h"

@interface MockWebSocketDelegate : NSObject <WebSocketConnectionDelegate>
@property (nonatomic, strong) NSData *lastMessage;
@property (nonatomic, strong) NSString *lastText;
@property (nonatomic, assign) NSInteger lastCloseCode;
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic, strong) XCTestExpectation *expectation;
@end

@implementation MockWebSocketDelegate
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveMessage:(NSData *)data {
    self.lastMessage = data;
    [self.expectation fulfill];
}
- (void)webSocketConnection:(WebSocketConnection *)connection didReceiveText:(NSString *)text {
    self.lastText = text;
    [self.expectation fulfill];
}
- (void)webSocketConnection:(WebSocketConnection *)connection didCloseWithCode:(NSInteger)code reason:(NSString *)reason {
    self.lastCloseCode = code;
    [self.expectation fulfill];
}
- (void)webSocketConnection:(WebSocketConnection *)connection didFailWithError:(NSError *)error {
    self.lastError = error;
    [self.expectation fulfill];
}
@end

@interface WebSocketConnection (Testing)
- (void)handleReceivedData:(NSData *)data;
@end

@interface WebSocketFrameParsingTests : XCTestCase
@property (nonatomic, strong) WebSocketConnection *connection;
@property (nonatomic, strong) MockWebSocketDelegate *delegate;
@end

@implementation WebSocketFrameParsingTests

- (void)setUp {
    [super setUp];
    self.connection = [[WebSocketConnection alloc] init];
    self.delegate = [[MockWebSocketDelegate alloc] init];
    self.connection.delegate = self.delegate;
}

#ifndef GNUSTEP
- (void)testExtendedPayloadParsing126 {
    // 126 bytes payload (needs 2 byte length)
    // Fin=1, Opcode=2 (Binary) -> 0x82
    // Mask=0, Len=126 -> 0x7E
    // Length bytes = 0x00, 0x7E (126)
    
    NSMutableData *payload = [NSMutableData dataWithLength:126];
    const uint8_t *bytes = payload.bytes; // Zeroes
    // Fill with pattern
    for (int i=0; i<126; i++) {
        ((uint8_t *)payload.mutableBytes)[i] = (uint8_t)i;
    }
    
    NSMutableData *frame = [NSMutableData data];
    uint8_t header[] = {0x82, 0x7E, 0x00, 0x7E};
    [frame appendBytes:header length:4];
    [frame appendData:payload];
    
    self.delegate.expectation = [self expectationWithDescription:@"Receive 126 byte message"];
    
    [self.connection handleReceivedData:frame];
    // The delegate will call [expectation fulfill]
    
    [self waitForExpectations:@[self.delegate.expectation] timeout:1.0];
    XCTAssertEqualObjects(self.delegate.lastMessage, payload);
}
#endif

#ifndef GNUSTEP
- (void)testExtendedPayloadParsing127 {
    // 65536 bytes payload (needs 8 byte length)
    // Fin=1, Opcode=2 (Binary) -> 0x82
    // Mask=0, Len=127 -> 0x7F
    // Length bytes = 0x00 00 00 00 00 01 00 00 (65536)
    
    NSUInteger len = 65536;
    NSMutableData *payload = [NSMutableData dataWithLength:len];
    // Fill with pattern
    ((uint8_t *)payload.mutableBytes)[0] = 0xAA;
    ((uint8_t *)payload.mutableBytes)[len-1] = 0xBB;
    
    NSMutableData *frame = [NSMutableData data];
    uint8_t header[] = {0x82, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00};
    [frame appendBytes:header length:10];
    [frame appendData:payload];
    
    self.delegate.expectation = [self expectationWithDescription:@"Receive 64KB message"];
    
    [self.connection handleReceivedData:frame];
    // The delegate will call [expectation fulfill]
    
    [self waitForExpectations:@[self.delegate.expectation] timeout:1.0];
    XCTAssertEqualObjects(self.delegate.lastMessage, payload);
}
#endif

#ifndef GNUSTEP
- (void)testMaskedFrameParsingMatchesLastTextObject {
    // Hello World masked
    // Fin=1, Opcode=1 (Text) -> 0x81
    // Mask=1, Len=5 -> 0x85
    // Mask Key = 0x37 0xFA 0x21 0x3D
    // "Hello" -> 0x48 0x65 0x6C 0x6C 0x6F
    // Masked:
    // H ^ 37 = 7F
    // e ^ FA = 9F
    // l ^ 21 = 4D
    // l ^ 3D = 51
    // o ^ 37 = 58
    
    uint8_t frameBytes[] = {
        0x81, 0x85, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x9F, 0x4D, 0x51, 0x58
    };
    NSData *frame = [NSData dataWithBytes:frameBytes length:sizeof(frameBytes)];
    
    self.delegate.expectation = [self expectationWithDescription:@"Receive masked text"];
    
    [self.connection handleReceivedData:frame];
    // The delegate will call [expectation fulfill]
    
    [self waitForExpectations:@[self.delegate.expectation] timeout:1.0];
    XCTAssertEqualObjects(self.delegate.lastText, @"Hello");
}
#endif

@end

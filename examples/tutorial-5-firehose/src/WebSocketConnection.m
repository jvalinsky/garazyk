#import "WebSocketConnection.h"
#import <sys/socket.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <CommonCrypto/CommonDigest.h>

@interface WebSocketConnection ()
@property (nonatomic, assign) int socket;
@property (nonatomic, copy, readwrite) NSString *remoteAddress;
@property (nonatomic, assign, readwrite) NSUInteger pendingSendCount;
@property (nonatomic, assign, readwrite) NSUInteger pendingSendBytes;
@property (nonatomic, strong) dispatch_queue_t sendQueue;
@property (nonatomic, strong) dispatch_queue_t receiveQueue;
@property (nonatomic, assign) BOOL isOpen;
@end

@implementation WebSocketConnection

- (instancetype)initWithSocket:(int)socket {
    self = [super init];
    if (!self) return nil;
    
    self.socket = socket;
    self.isOpen = YES;
    self.pendingSendCount = 0;
    self.pendingSendBytes = 0;
    
    // Get remote address
    struct sockaddr_in addr;
    socklen_t addrLen = sizeof(addr);
    getpeername(socket, (struct sockaddr *)&addr, &addrLen);
    char ipStr[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &addr.sin_addr, ipStr, sizeof(ipStr));
    self.remoteAddress = [NSString stringWithUTF8String:ipStr];
    
    self.sendQueue = dispatch_queue_create("com.atproto.websocket.send", DISPATCH_QUEUE_SERIAL);
    self.receiveQueue = dispatch_queue_create("com.atproto.websocket.receive", DISPATCH_QUEUE_SERIAL);
    
    return self;
}

- (void)start {
    dispatch_async(self.receiveQueue, ^{
        [self receiveLoop];
    });
}

- (void)sendMessage:(NSData *)message {
    if (!self.isOpen) return;
    
    dispatch_async(self.sendQueue, ^{
        self.pendingSendCount++;
        self.pendingSendBytes += message.length;
        
        // Build WebSocket frame (binary, FIN=1)
        NSMutableData *frame = [NSMutableData data];
        
        uint8_t byte1 = 0x82;  // FIN=1, opcode=binary
        [frame appendBytes:&byte1 length:1];
        
        // Payload length
        if (message.length < 126) {
            uint8_t byte2 = (uint8_t)message.length;
            [frame appendBytes:&byte2 length:1];
        } else if (message.length < 65536) {
            uint8_t byte2 = 126;
            [frame appendBytes:&byte2 length:1];
            uint16_t len = htons((uint16_t)message.length);
            [frame appendBytes:&len length:2];
        } else {
            uint8_t byte2 = 127;
            [frame appendBytes:&byte2 length:1];
            uint64_t len = htonll((uint64_t)message.length);
            [frame appendBytes:&len length:8];
        }
        
        [frame appendData:message];
        
        // Send frame
        ssize_t sent = send(self.socket, frame.bytes, frame.length, 0);
        
        self.pendingSendCount--;
        self.pendingSendBytes -= message.length;
        
        if (sent < 0) {
            NSLog(@"Failed to send WebSocket message");
            [self close];
        }
    });
}

- (void)receiveLoop {
    while (self.isOpen) {
        // Read frame header
        uint8_t header[2];
        ssize_t n = recv(self.socket, header, 2, 0);
        
        if (n <= 0) {
            [self close];
            break;
        }
        
        uint8_t opcode = header[0] & 0x0F;
        BOOL masked = (header[1] & 0x80) != 0;
        uint64_t payloadLen = header[1] & 0x7F;
        
        // Read extended payload length if needed
        if (payloadLen == 126) {
            uint16_t len16;
            recv(self.socket, &len16, 2, 0);
            payloadLen = ntohs(len16);
        } else if (payloadLen == 127) {
            uint64_t len64;
            recv(self.socket, &len64, 8, 0);
            payloadLen = ntohll(len64);
        }
        
        // Read masking key if present
        uint8_t maskingKey[4] = {0};
        if (masked) {
            recv(self.socket, maskingKey, 4, 0);
        }
        
        // Read payload
        NSMutableData *payload = [NSMutableData dataWithLength:payloadLen];
        ssize_t totalRead = 0;
        while (totalRead < payloadLen) {
            ssize_t bytesRead = recv(self.socket, 
                                    (uint8_t *)payload.mutableBytes + totalRead,
                                    payloadLen - totalRead, 0);
            if (bytesRead <= 0) {
                [self close];
                return;
            }
            totalRead += bytesRead;
        }
        
        // Unmask payload if needed
        if (masked) {
            uint8_t *bytes = (uint8_t *)payload.mutableBytes;
            for (NSUInteger i = 0; i < payloadLen; i++) {
                bytes[i] ^= maskingKey[i % 4];
            }
        }
        
        // Handle opcode
        if (opcode == 0x08) {  // Close
            [self close];
            break;
        } else if (opcode == 0x09) {  // Ping
            [self sendPong:payload];
        } else if (opcode == 0x02 || opcode == 0x01) {  // Binary or Text
            if (self.messageHandler) {
                self.messageHandler(payload);
            }
        }
    }
}

- (void)sendPong:(NSData *)payload {
    NSMutableData *frame = [NSMutableData data];
    uint8_t byte1 = 0x8A;  // FIN=1, opcode=pong
    [frame appendBytes:&byte1 length:1];
    uint8_t byte2 = (uint8_t)payload.length;
    [frame appendBytes:&byte2 length:1];
    [frame appendData:payload];
    send(self.socket, frame.bytes, frame.length, 0);
}

- (void)close {
    [self closeWithCode:1000 reason:@"Normal closure"];
}

- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    if (!self.isOpen) return;
    
    self.isOpen = NO;
    
    // Send close frame
    NSMutableData *frame = [NSMutableData data];
    uint8_t byte1 = 0x88;  // FIN=1, opcode=close
    [frame appendBytes:&byte1 length:1];
    
    uint16_t closeCode = htons((uint16_t)code);
    NSData *reasonData = [reason dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t byte2 = (uint8_t)(2 + reasonData.length);
    [frame appendBytes:&byte2 length:1];
    [frame appendBytes:&closeCode length:2];
    [frame appendData:reasonData];
    
    send(self.socket, frame.bytes, frame.length, 0);
    close(self.socket);
    
    if (self.closeHandler) {
        self.closeHandler(code, reason);
    }
}

@end

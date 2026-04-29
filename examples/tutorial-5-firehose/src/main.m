#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#if defined(__APPLE__) && !defined(GNUSTEP)
#import <CommonCrypto/CommonDigest.h>
#else
#import <openssl/sha.h>
#endif
#import "WebSocketConnection.h"
#import "SubscribeReposHandler.h"

@interface SimpleHTTPServer : NSObject
@property (nonatomic, assign) int serverSocket;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) SubscribeReposHandler *firehoseHandler;
@property (nonatomic, assign) BOOL isRunning;

- (instancetype)initWithPort:(uint16_t)port;
- (BOOL)start;
- (void)acceptLoop;
- (void)handleClient:(int)clientSocket;
- (void)handleWebSocketUpgrade:(int)clientSocket 
                        headers:(NSDictionary *)headers
                           path:(NSString *)path;
@end

@implementation SimpleHTTPServer

- (instancetype)initWithPort:(uint16_t)port {
    self = [super init];
    if (!self) return nil;
    
    self.port = port;
    self.firehoseHandler = [[SubscribeReposHandler alloc] init];
    self.isRunning = NO;
    
    return self;
}

- (BOOL)start {
    // Create socket
    self.serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (self.serverSocket < 0) {
        NSLog(@"Failed to create socket");
        return NO;
    }
    
    // Set socket options
    int optval = 1;
    setsockopt(self.serverSocket, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
    
    // Bind to port
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(self.port);
    
    if (bind(self.serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"Failed to bind to port %d", self.port);
        return NO;
    }
    
    // Listen
    if (listen(self.serverSocket, SOMAXCONN) < 0) {
        NSLog(@"Failed to listen");
        return NO;
    }
    
    self.isRunning = YES;
    NSLog(@"Server started on port %d", self.port);
    NSLog(@"Firehose available at ws://localhost:%d/xrpc/com.atproto.sync.subscribeRepos", self.port);
    
    // Accept connections in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self acceptLoop];
    });
    
    return YES;
}

- (void)acceptLoop {
    while (self.isRunning) {
        struct sockaddr_in clientAddr;
        socklen_t clientAddrLen = sizeof(clientAddr);
        
        int clientSocket = accept(self.serverSocket, 
                                 (struct sockaddr *)&clientAddr, 
                                 &clientAddrLen);
        
        if (clientSocket < 0) continue;
        
        // Handle client in background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientSocket];
        });
    }
}

- (void)handleClient:(int)clientSocket {
    // Read request
    char buffer[4096];
    ssize_t n = recv(clientSocket, buffer, sizeof(buffer), 0);
    
    if (n <= 0) {
        close(clientSocket);
        return;
    }
    
    NSString *requestStr = [[NSString alloc] initWithBytes:buffer 
                                                    length:n 
                                                  encoding:NSUTF8StringEncoding];
    
    // Parse request
    NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        close(clientSocket);
        return;
    }
    
    NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
    if (requestLine.count < 2) {
        close(clientSocket);
        return;
    }
    
    NSString *path = requestLine[1];
    
    // Parse headers
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        if (line.length == 0) break;
        
        NSArray *parts = [line componentsSeparatedByString:@": "];
        if (parts.count == 2) {
            headers[parts[0]] = parts[1];
        }
    }
    
    // Check for WebSocket upgrade
    if ([headers[@"Upgrade"] caseInsensitiveCompare:@"websocket"] == NSOrderedSame &&
        [path hasPrefix:@"/xrpc/com.atproto.sync.subscribeRepos"]) {
        [self handleWebSocketUpgrade:clientSocket headers:headers path:path];
        return;
    }
    
    // Regular HTTP response
    NSString *response = @"HTTP/1.1 200 OK\r\n"
                         @"Content-Type: application/json\r\n"
                         @"\r\n"
                         @"{\"message\":\"Use WebSocket for subscribeRepos\"}";
    send(clientSocket, [response UTF8String], response.length, 0);
    close(clientSocket);
}

- (void)handleWebSocketUpgrade:(int)clientSocket 
                        headers:(NSDictionary *)headers
                           path:(NSString *)path {
    
    // Extract WebSocket key
    NSString *wsKey = headers[@"Sec-WebSocket-Key"];
    if (!wsKey) {
        close(clientSocket);
        return;
    }
    
    // Compute accept key
    NSString *magic = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    NSString *combined = [wsKey stringByAppendingString:magic];
    NSData *combinedData = [combined dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[20]; // SHA-1 = 20 bytes
#if defined(__APPLE__) && !defined(GNUSTEP)
    CC_SHA1(combinedData.bytes, (CC_LONG)combinedData.length, digest);
#else
    SHA1(combinedData.bytes, combinedData.length, digest);
#endif
    NSData *digestData = [NSData dataWithBytes:digest length:20];
    NSString *acceptKey = [digestData base64EncodedStringWithOptions:0];
    
    // Send upgrade response
    NSString *response = [NSString stringWithFormat:
        @"HTTP/1.1 101 Switching Protocols\r\n"
        @"Upgrade: websocket\r\n"
        @"Connection: Upgrade\r\n"
        @"Sec-WebSocket-Accept: %@\r\n"
        @"\r\n", acceptKey];
    
    send(clientSocket, [response UTF8String], response.length, 0);
    
    // Extract cursor from query string
    NSString *cursor = nil;
    NSArray *pathParts = [path componentsSeparatedByString:@"?"];
    if (pathParts.count > 1) {
        NSString *query = pathParts[1];
        NSArray *params = [query componentsSeparatedByString:@"&"];
        for (NSString *param in params) {
            NSArray *kv = [param componentsSeparatedByString:@"="];
            if (kv.count == 2 && [kv[0] isEqualToString:@"cursor"]) {
                cursor = kv[1];
            }
        }
    }
    
    // Create WebSocket connection
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithSocket:clientSocket];
    [connection start];
    
    // Hand off to SubscribeRepos handler
    [self.firehoseHandler acceptConnection:connection cursor:cursor];
    
    NSLog(@"WebSocket connection established");
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 5: Firehose Example");
        NSLog(@"==============================");
        
        // Create and start server
        SimpleHTTPServer *server = [[SimpleHTTPServer alloc] initWithPort:2583];
        if (![server start]) {
            NSLog(@"Failed to start server");
            return 1;
        }
        
        // Simulate some commit events for testing
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 
                      dispatch_get_main_queue(), ^{
            NSLog(@"Broadcasting test commit event...");
            
            NSData *commitCID = [@"test-commit-cid" dataUsingEncoding:NSUTF8StringEncoding];
            NSData *carBlocks = [@"test-car-blocks" dataUsingEncoding:NSUTF8StringEncoding];
            NSArray *ops = @[@{
                @"action": @"create",
                @"path": @"app.bsky.feed.post/test123",
                @"cid": @"bafytest123"
            }];
            
            [server.firehoseHandler broadcastCommit:@"did:plc:test123"
                                                rev:@"rev1"
                                             commit:commitCID
                                             blocks:carBlocks
                                                ops:ops];
        });
        
        // Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}

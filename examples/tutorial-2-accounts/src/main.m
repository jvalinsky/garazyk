#import <Foundation/Foundation.h>
#import "AccountService.h"
#import "AccountRepository.h"
#import "TutorialJWTMinter.h"
#import "TutorialJWTVerifier.h"

// POSIX socket headers (must be imported explicitly for macOS modules)
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <string.h>

// Simple HTTP request/response structures
@interface SimpleHttpRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, strong) NSData *body;
@end

@implementation SimpleHttpRequest
@end

@interface SimpleHttpResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSMutableDictionary *headers;
@property (nonatomic, strong) NSData *body;
- (void)setJsonBody:(NSDictionary *)json;
@end

@implementation SimpleHttpResponse

- (instancetype)init {
    self = [super init];
    if (self) {
        _statusCode = 200;
        _headers = [NSMutableDictionary dictionaryWithDictionary:@{@"Content-Type": @"application/json"}];
    }
    return self;
}

- (void)setJsonBody:(NSDictionary *)json {
    self.body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    self.headers[@"Content-Type"] = @"application/json";
}

@end

// Simple XRPC Dispatcher
@interface SimpleXrpcDispatcher : NSObject
@property (nonatomic, strong) AccountService *accountService;
@property (nonatomic, strong) TutorialJWTVerifier *tokenVerifier;
@end

@implementation SimpleXrpcDispatcher

- (void)dispatchRequest:(SimpleHttpRequest *)request
               response:(SimpleHttpResponse *)response {
    NSString *path = request.path;
    NSString *nsid = [path stringByReplacingOccurrencesOfString:@"/xrpc/" withString:@""];

    if ([nsid isEqualToString:@"com.atproto.server.describeServer"]) {
        [self handleDescribeServer:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createAccount"]) {
        [self handleCreateAccount:request response:response];
    } else if ([nsid isEqualToString:@"com.atproto.server.createSession"]) {
        [self handleCreateSession:request response:response];
    } else {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"MethodNotFound"}];
    }
}

- (void)handleDescribeServer:(SimpleHttpRequest *)request
                    response:(SimpleHttpResponse *)response {
    [response setJsonBody:@{
        @"did": @"did:web:localhost:2583",
        @"availableUserDomains": @[@"localhost"],
        @"inviteCodeRequired": @NO,
        @"phoneNumberRequired": @NO
    }];
}

- (void)handleCreateAccount:(SimpleHttpRequest *)request
                   response:(SimpleHttpResponse *)response {
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body
                                                           options:0
                                                             error:&parseError];
    if (!params) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [self.accountService createAccountForEmail:params[@"email"]
                                                             password:params[@"password"]
                                                              handle:params[@"handle"]
                                                               error:&error];
    if (!result) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Account creation failed"}];
        return;
    }

    [response setJsonBody:result];
}

- (void)handleCreateSession:(SimpleHttpRequest *)request
                   response:(SimpleHttpResponse *)response {
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body
                                                           options:0
                                                             error:&parseError];
    if (!params) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"InvalidRequest"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [self.accountService loginWithHandle:params[@"identifier"]
                                                       password:params[@"password"]
                                                          error:&error];
    if (!result) {
        response.statusCode = 401;
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Login failed"}];
        return;
    }

    [response setJsonBody:result];
}

@end

// Simple HTTP Server (actually binds a socket)
@interface SimpleHttpServer : NSObject
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, strong) SimpleXrpcDispatcher *dispatcher;
@property (nonatomic, assign) BOOL isRunning;
- (void)startWithCompletion:(void (^)(NSError * _Nullable error))completion;
@end

@implementation SimpleHttpServer

- (void)startWithCompletion:(void (^)(NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Create TCP socket
        int serverFd = socket(AF_INET, SOCK_STREAM, 0);
        if (serverFd < 0) {
            NSError *error = [NSError errorWithDomain:@"HTTP" code:errno
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 [NSString stringWithUTF8String:strerror(errno)]}];
            completion(error);
            return;
        }

        // Allow address reuse
        int opt = 1;
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = htons((uint16_t)self.port);

        if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(serverFd);
            NSError *error = [NSError errorWithDomain:@"HTTP" code:errno
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:@"Failed to bind port %ld: %s",
                                                     (long)self.port, strerror(errno)]}];
            completion(error);
            return;
        }

        if (listen(serverFd, 5) < 0) {
            close(serverFd);
            NSError *error = [NSError errorWithDomain:@"HTTP" code:errno
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 [NSString stringWithUTF8String:strerror(errno)]}];
            completion(error);
            return;
        }

        self.isRunning = YES;
        NSLog(@"HTTP Server listening on http://localhost:%ld", (long)self.port);
        completion(nil);

        // Accept connections
        while (self.isRunning) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientFd = accept(serverFd, (struct sockaddr *)&clientAddr, &clientLen);
            if (clientFd < 0) continue;

            // Read request (simplified — reads up to 4096 bytes)
            char buffer[4096];
            ssize_t bytesRead = recv(clientFd, buffer, sizeof(buffer) - 1, 0);
            if (bytesRead <= 0) {
                close(clientFd);
                continue;
            }
            buffer[bytesRead] = '\0';

            // Parse HTTP request line
            NSString *requestStr = [NSString stringWithUTF8String:buffer];
            NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
            NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];

            if (requestLine.count < 3) {
                close(clientFd);
                continue;
            }

            SimpleHttpRequest *request = [[SimpleHttpRequest alloc] init];
            request.method = requestLine[0];
            request.path = requestLine[1];

            // Find body (after \r\n\r\n)
            NSRange bodyRange = [requestStr rangeOfString:@"\r\n\r\n"];
            if (bodyRange.location != NSNotFound && bodyRange.location + 4 < requestStr.length) {
                NSString *bodyStr = [requestStr substringFromIndex:bodyRange.location + 4];
                request.body = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
            } else {
                request.body = [NSData data];
            }

            // Dispatch to handler
            SimpleHttpResponse *response = [[SimpleHttpResponse alloc] init];
            [self.dispatcher dispatchRequest:request response:response];

            // Send response
            NSMutableData *responseData = [NSMutableData data];
            NSString *statusText = response.statusCode == 200 ? @"OK" :
                                   response.statusCode == 400 ? @"Bad Request" :
                                   response.statusCode == 401 ? @"Unauthorized" :
                                   response.statusCode == 404 ? @"Not Found" : @"Error";
            NSString *headerStr = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\n",
                                   (long)response.statusCode, statusText];
            for (NSString *key in response.headers) {
                headerStr = [headerStr stringByAppendingFormat:@"%@: %@\r\n", key, response.headers[key]];
            }
            headerStr = [headerStr stringByAppendingString:@"\r\n"];
            [responseData appendData:[headerStr dataUsingEncoding:NSUTF8StringEncoding]];
            if (response.body) {
                [responseData appendData:response.body];
            }

            send(clientFd, responseData.bytes, responseData.length, 0);
            close(clientFd);
        }

        close(serverFd);
    });
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 2: Account Management");
        NSLog(@"===============================");

        // 1. Setup paths
        NSString *homeDir = NSHomeDirectory();
        NSString *dataDir = [homeDir stringByAppendingPathComponent:@".tutorial-2-accounts"];
        NSString *dbPath = [dataDir stringByAppendingPathComponent:@"db"];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dataDir]) {
            [fm createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        NSLog(@"Data directory: %@", dataDir);

        // 2. Create account service with ES256 JWT signing
        AccountRepository *accountRepo = [[AccountRepository alloc] initWithDatabasePath:dbPath];
        TutorialJWTMinter *minter = [[TutorialJWTMinter alloc] initWithIssuer:@"did:web:localhost:2583"];
        AccountService *accountService = [[AccountService alloc] initWithRepository:accountRepo minter:minter];

        NSLog(@"Account service initialized (ES256 JWT signing)");

        // 3. Setup XRPC dispatcher
        SimpleXrpcDispatcher *dispatcher = [[SimpleXrpcDispatcher alloc] init];
        dispatcher.accountService = accountService;
        dispatcher.tokenVerifier = [[TutorialJWTVerifier alloc] initWithIssuer:@"did:web:localhost:2583"
                                                                       keyPair:minter.keyPair];

        // 4. Create and start HTTP server
        SimpleHttpServer *server = [[SimpleHttpServer alloc] init];
        server.port = 2583;
        server.dispatcher = dispatcher;

        [server startWithCompletion:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to start server: %@", error);
                exit(1);
            }

            NSLog(@"PDS started on port %ld", (long)server.port);
            NSLog(@"Account service ready");
            NSLog(@"");
            NSLog(@"Test with curl:");
            NSLog(@"  Create account:");
            NSLog(@"    curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \\");
            NSLog(@"      -H 'Content-Type: application/json' \\");
            NSLog(@"      -d '{\"email\":\"alice@example.com\",\"password\":\"password\",\"handle\":\"alice\"}'");
            NSLog(@"");
            NSLog(@"  Login:");
            NSLog(@"    curl -X POST http://localhost:2583/xrpc/com.atproto.server.createSession \\");
            NSLog(@"      -H 'Content-Type: application/json' \\");
            NSLog(@"      -d '{\"identifier\":\"alice\",\"password\":\"password\"}'");
        }];

        // 5. Keep running
        [[NSRunLoop mainRunLoop] run];
    }

    return 0;
}

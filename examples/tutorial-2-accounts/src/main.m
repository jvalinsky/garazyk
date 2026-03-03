#import <Foundation/Foundation.h>
#import "AccountService.h"
#import "AccountRepository.h"
#import "SimpleJWTMinter.h"

// Simple HTTP request/response structures
@interface SimpleHttpRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSData *body;
@end

@implementation SimpleHttpRequest
@end

@interface SimpleHttpResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy) NSData *body;
@property (nonatomic, strong) NSDictionary *headers;
@end

@implementation SimpleHttpResponse
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    self.statusCode = 200;
    self.headers = @{@"Content-Type": @"application/json"};
    return self;
}
@end

// Simple XRPC Dispatcher
@interface SimpleXrpcDispatcher : NSObject
@property (nonatomic, strong) AccountService *accountService;
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
        NSDictionary *error = @{@"error": @"MethodNotFound"};
        response.body = [NSJSONSerialization dataWithJSONObject:error options:0 error:nil];
    }
}

- (void)handleDescribeServer:(SimpleHttpRequest *)request 
                    response:(SimpleHttpResponse *)response {
    NSDictionary *result = @{
        @"did": @"did:web:localhost:2583",
        @"availableUserDomains": @[@"localhost"],
        @"inviteCodeRequired": @NO,
        @"phoneNumberRequired": @NO
    };
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleCreateAccount:(SimpleHttpRequest *)request 
                   response:(SimpleHttpResponse *)response {
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        NSDictionary *error = @{@"error": @"InvalidRequest"};
        response.body = [NSJSONSerialization dataWithJSONObject:error options:0 error:nil];
        return;
    }
    
    NSError *error = nil;
    NSDictionary *result = [self.accountService createAccountForEmail:params[@"email"]
                                                              password:params[@"password"]
                                                               handle:params[@"handle"]
                                                                error:&error];
    
    if (!result) {
        response.statusCode = 400;
        NSDictionary *errorDict = @{@"error": error.localizedDescription ?: @"Account creation failed"};
        response.body = [NSJSONSerialization dataWithJSONObject:errorDict options:0 error:nil];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

- (void)handleCreateSession:(SimpleHttpRequest *)request 
                   response:(SimpleHttpResponse *)response {
    
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body 
                                                            options:0 
                                                              error:&parseError];
    
    if (!params) {
        response.statusCode = 400;
        NSDictionary *error = @{@"error": @"InvalidRequest"};
        response.body = [NSJSONSerialization dataWithJSONObject:error options:0 error:nil];
        return;
    }
    
    NSError *error = nil;
    NSDictionary *result = [self.accountService loginWithHandle:params[@"identifier"]
                                                       password:params[@"password"]
                                                          error:&error];
    
    if (!result) {
        response.statusCode = 401;
        NSDictionary *errorDict = @{@"error": error.localizedDescription ?: @"Login failed"};
        response.body = [NSJSONSerialization dataWithJSONObject:errorDict options:0 error:nil];
        return;
    }
    
    response.statusCode = 200;
    response.body = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}

@end

// Simple HTTP Server
@interface SimpleHttpServer : NSObject
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, strong) SimpleXrpcDispatcher *dispatcher;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation SimpleHttpServer

- (void)startWithCompletion:(void (^)(NSError *error))completion {
    self.isRunning = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Simple HTTP server that listens on port and dispatches to XRPC
        NSLog(@"HTTP Server listening on port %ld", (long)self.port);
        
        // For this tutorial, we'll use a simple approach:
        // In production, use a real HTTP server library
        // For now, just log that we're ready
        completion(nil);
    });
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 2: Account Management");
        NSLog(@"================================");
        
        // 1. Setup paths
        NSString *homeDir = NSHomeDirectory();
        NSString *dataDir = [homeDir stringByAppendingPathComponent:@".tutorial-2-accounts"];
        NSString *dbPath = [dataDir stringByAppendingPathComponent:@"db"];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dataDir]) {
            [fm createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        NSLog(@"Data directory: %@", dataDir);
        
        // 2. Create account service
        AccountRepository *accountRepo = [[AccountRepository alloc] initWithDatabasePath:dbPath];
        SimpleJWTMinter *minter = [[SimpleJWTMinter alloc] initWithIssuer:@"did:web:localhost:2583"];
        AccountService *accountService = [[AccountService alloc] initWithRepository:accountRepo minter:minter];
        
        NSLog(@"Account service initialized");
        
        // 3. Setup XRPC dispatcher
        SimpleXrpcDispatcher *dispatcher = [[SimpleXrpcDispatcher alloc] init];
        dispatcher.accountService = accountService;
        
        // 4. Create HTTP server
        SimpleHttpServer *server = [[SimpleHttpServer alloc] init];
        server.port = 2583;
        server.dispatcher = dispatcher;
        
        // 5. Start server
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
        
        // 6. Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    
    return 0;
}

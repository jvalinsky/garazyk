#import "TestUtilities.h"
#import "PDSDatabase.h"

#pragma mark - TestFixture Implementation

@implementation TestFixture

+ (instancetype)sharedFixture {
    static TestFixture *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[TestFixture alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _testData = [@"Test data for unit tests" dataUsingEncoding:NSUTF8StringEncoding];
        _testDID = @"did:plc:test1234567890";
        _testHandle = @"test.example.com";
        _testCID = [self generateRandomCID];
        _testTID = [TID tid];
    }
    return self;
}

- (NSData *)randomDataOfLength:(NSUInteger)length {
    uint8_t *bytes = malloc(length);
    arc4random_buf(bytes, length);
    NSData *data = [NSData dataWithBytes:bytes length:length];
    free(bytes);
    return data;
}

- (NSString *)randomStringOfLength:(NSUInteger)length {
    NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
        [result appendFormat:@"%C", c];
    }
    return result;
}

- (CID *)generateRandomCID {
    uint8_t multihash[36] = {0x12, 0x20};
    arc4random_buf(&multihash[2], 34);
    NSData *mh = [NSData dataWithBytes:multihash length:sizeof(multihash)];
    return [CID cidWithMultihash:mh codec:0x71];
}

- (NSString *)generateRandomHandle {
    NSString *randomPart = [self randomStringOfLength:8];
    return [NSString stringWithFormat:@"%@.test", randomPart];
}

@end

#pragma mark - MockHTTPServer Implementation

@interface MockHTTPServer ()
@property (nonatomic, strong) NSHTTPServer *httpServer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(NSDictionary *, void (^)(NSInteger, NSDictionary *, NSData *))> *routes;
@property (nonatomic, assign) UInt16 port;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@end

@implementation MockHTTPServer

+ (nullable instancetype)serverWithPort:(UInt16)port error:(NSError **)error {
    MockHTTPServer *server = [[MockHTTPServer alloc] init];
    server.port = port;
    server.routes = [NSMutableDictionary dictionary];
    server.httpServer = [[NSHTTPServer alloc] init];
    [server.httpServer setType:@"_http._tcp"];
    
    NSError *bindError = nil;
    [server.httpServer setPort:port];
    if (![server.httpServer startListening:&bindError]) {
        if (error) *error = bindError;
        return nil;
    }
    return server;
}

- (BOOL)startWithError:(NSError **)error {
    if (self.running) return YES;
    return [self.httpServer startListening:error];
}

- (void)stop {
    [self.httpServer stop];
    self.running = NO;
}

- (void)addRouteForMethod:(NSString *)method
                      path:(NSString *)path
                handler:(void (^)(NSDictionary *request, void (^response)(NSInteger status, NSDictionary *headers, NSData *body)))handler {
    NSString *key = [NSString stringWithFormat:@"%@ %@", method.uppercaseString, path];
    self.routes[key] = handler;
}

@end

#pragma mark - TestDatabase Implementation

@interface TestDatabase ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation TestDatabase

+ (nullable instancetype)inMemoryDatabaseWithError:(NSError **)error {
    TestDatabase *td = [[TestDatabase alloc] init];
    td.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:@":memory:"]];
    if (![td.database openWithError:error]) {
        return nil;
    }
    return td;
}

+ (nullable instancetype)temporaryDatabaseWithError:(NSError **)error {
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"test_%@.db", [[NSUUID UUID] UUIDString]]];
    TestDatabase *td = [[TestDatabase alloc] init];
    td.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:tempPath]];
    if (![td.database openWithError:error]) {
        return nil;
    }
    return td;
}

- (BOOL)resetWithError:(NSError **)error {
    [self.database close];
    return [self.database openWithError:error];
}

- (void)close {
    [self.database close];
}

- (class)PDSDatabase {
    return [PDSDatabase class];
}

@end

#pragma mark - ConcurrencyTestHelper Implementation

@implementation ConcurrencyTestHelper

+ (dispatch_queue_t)createTestQueue {
    return dispatch_queue_create("com.atproto.pds.test.concurrent",
                                  DISPATCH_QUEUE_CONCURRENT);
}

+ (void)waitForQueue:(dispatch_queue_t)queue timeout:(NSTimeInterval)timeout {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    dispatch_semaphore_wait(semaphore, timeoutTime);
}

+ (void)runSynchronousBlock:(void (^)(void))block timeout:(NSTimeInterval)timeout {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        block();
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    dispatch_semaphore_wait(semaphore, timeoutTime);
}

@end

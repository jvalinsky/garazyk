#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "Network/HttpServer.h"
#import "Network/PDSNetworkTransport.h"

typedef id<PDSNetworkListener> (^PDSListenerFactory)(NSUInteger port);

static PDSListenerFactory sListenerFactory = nil;
static IMP sOriginalCreateListenerIMP = NULL;

static id<PDSNetworkListener> TestCreateListener(id self, SEL _cmd, NSUInteger port) {
    if (sListenerFactory) {
        return sListenerFactory(port);
    }
    return nil;
}

@interface PDSFakeListener : NSObject <PDSNetworkListener>
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(PDSNetworkListenerState state, NSError * _Nullable error);
@property (nonatomic, copy, nullable) void (^newConnectionHandler)(id<PDSNetworkConnection> connection);
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, assign) PDSNetworkListenerState stateToReport;
@property (nonatomic, strong, nullable) NSError *errorToReport;
@end

@implementation PDSFakeListener

- (instancetype)initWithPort:(NSUInteger)port state:(PDSNetworkListenerState)state error:(NSError *)error {
    self = [super init];
    if (self) {
        _port = port;
        _stateToReport = state;
        _errorToReport = error;
    }
    return self;
}

- (void)startWithQueue:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{
        if (self.stateChangedHandler) {
            self.stateChangedHandler(self.stateToReport, self.errorToReport);
        }
    });
}

- (void)cancel {
    if (self.stateChangedHandler) {
        self.stateChangedHandler(PDSNetworkListenerStateCancelled, nil);
    }
}

@end

@interface HttpServerTests : XCTestCase
@end

@implementation HttpServerTests

- (void)setUp {
    [super setUp];
    [self swizzleListenerFactory];
}

- (void)tearDown {
    [self restoreListenerFactory];
    sListenerFactory = nil;
    [super tearDown];
}

- (void)swizzleListenerFactory {
    Method method = class_getClassMethod([PDSNetworkTransportFactory class], @selector(createListenerWithPort:));
    if (!method) {
        return;
    }
    if (!sOriginalCreateListenerIMP) {
        sOriginalCreateListenerIMP = method_getImplementation(method);
    }
    method_setImplementation(method, (IMP)TestCreateListener);
}

- (void)restoreListenerFactory {
    if (!sOriginalCreateListenerIMP) {
        return;
    }
    Method method = class_getClassMethod([PDSNetworkTransportFactory class], @selector(createListenerWithPort:));
    if (method) {
        method_setImplementation(method, sOriginalCreateListenerIMP);
    }
}

- (void)testStartFailsWhenListenerFactoryReturnsNil {
    sListenerFactory = nil;
    HttpServer *server = [HttpServer serverWithPort:0];

    NSError *error = nil;
    BOOL started = [server startWithError:&error];

    XCTAssertFalse(started);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, -1);
}

- (void)testStartFailsWhenListenerReportsFailure {
    sListenerFactory = ^id<PDSNetworkListener>(NSUInteger port) {
        NSError *listenerError = [NSError errorWithDomain:@"test.listener" code:42 userInfo:nil];
        return [[PDSFakeListener alloc] initWithPort:port state:PDSNetworkListenerStateFailed error:listenerError];
    };
    HttpServer *server = [HttpServer serverWithPort:0];

    NSError *error = nil;
    BOOL started = [server startWithError:&error];

    XCTAssertFalse(started);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, -3);
}

- (void)testStartSucceedsWhenListenerReady {
    sListenerFactory = ^id<PDSNetworkListener>(NSUInteger port) {
        return [[PDSFakeListener alloc] initWithPort:12345 state:PDSNetworkListenerStateReady error:nil];
    };
    HttpServer *server = [HttpServer serverWithPort:0];

    NSError *error = nil;
    BOOL started = [server startWithError:&error];

    XCTAssertTrue(started);
    XCTAssertNil(error);
    XCTAssertEqual(server.port, 12345);
}

@end

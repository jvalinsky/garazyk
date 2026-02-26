#import <XCTest/XCTest.h>
#import "App/AppDelegate.h"
#import <objc/runtime.h>

@interface AppDelegate (TestHooks)
- (void)startServer:(id)sender;
- (void)stopServer:(id)sender;
#if TARGET_OS_OSX || defined(__APPLE__)
- (void)setupStatusBar;
#endif
@end

@interface AppDelegateMockController : NSObject
@property (nonatomic, assign) BOOL startShouldSucceed;
@property (nonatomic, assign) NSInteger startCalls;
@property (nonatomic, assign) NSInteger stopCalls;
@end

@implementation AppDelegateMockController

- (BOOL)startServerWithError:(NSError **)error {
    self.startCalls += 1;
    if (self.startShouldSucceed) {
        return YES;
    }
    if (error) {
        *error = [NSError errorWithDomain:@"AppDelegateTests"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : @"start failed"}];
    }
    return NO;
}

- (void)stopServer {
    self.stopCalls += 1;
}

@end

@interface AppDelegateTests : XCTestCase
@end

static IMP gOriginalPDSStartIMP = NULL;
static BOOL gStubStartReturn = YES;
static NSInteger gStubStartCallCount = 0;
#if TARGET_OS_OSX || defined(__APPLE__)
static IMP gOriginalSetupStatusBarIMP = NULL;
static NSInteger gStubSetupStatusBarCallCount = 0;
#endif

static BOOL StubPDSControllerStartServerWithError(id self, SEL _cmd, NSError **error) {
    (void)self;
    (void)_cmd;
    gStubStartCallCount += 1;
    if (!gStubStartReturn && error) {
        *error = [NSError errorWithDomain:@"AppDelegateTests"
                                     code:42
                                 userInfo:@{NSLocalizedDescriptionKey: @"stubbed start failure"}];
    }
    return gStubStartReturn;
}

#if TARGET_OS_OSX || defined(__APPLE__)
static void StubAppDelegateSetupStatusBar(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
    gStubSetupStatusBarCallCount += 1;
}
#endif

@implementation AppDelegateTests

- (void)setUp {
    [super setUp];
    gStubStartReturn = YES;
    gStubStartCallCount = 0;

    Method startMethod = class_getInstanceMethod([PDSController class], @selector(startServerWithError:));
    gOriginalPDSStartIMP = method_getImplementation(startMethod);
    method_setImplementation(startMethod, (IMP)StubPDSControllerStartServerWithError);
#if TARGET_OS_OSX || defined(__APPLE__)
    gStubSetupStatusBarCallCount = 0;
    Method setupMethod = class_getInstanceMethod([AppDelegate class], @selector(setupStatusBar));
    if (setupMethod) {
        gOriginalSetupStatusBarIMP = method_getImplementation(setupMethod);
        method_setImplementation(setupMethod, (IMP)StubAppDelegateSetupStatusBar);
    }
#endif
}

- (void)tearDown {
    Method startMethod = class_getInstanceMethod([PDSController class], @selector(startServerWithError:));
    if (gOriginalPDSStartIMP) {
        method_setImplementation(startMethod, gOriginalPDSStartIMP);
    }
#if TARGET_OS_OSX || defined(__APPLE__)
    Method setupMethod = class_getInstanceMethod([AppDelegate class], @selector(setupStatusBar));
    if (setupMethod && gOriginalSetupStatusBarIMP) {
        method_setImplementation(setupMethod, gOriginalSetupStatusBarIMP);
    }
#endif
    [super tearDown];
}

- (void)testStartServerInvokesController {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    AppDelegateMockController *mock = [[AppDelegateMockController alloc] init];
    mock.startShouldSucceed = YES;
    delegate.pdsController = (id)mock;

    [delegate startServer:nil];
    XCTAssertEqual(mock.startCalls, 1);
}

- (void)testStartServerFailureStillInvokesController {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    AppDelegateMockController *mock = [[AppDelegateMockController alloc] init];
    mock.startShouldSucceed = NO;
    delegate.pdsController = (id)mock;

    [delegate startServer:nil];
    XCTAssertEqual(mock.startCalls, 1);
}

- (void)testStopServerInvokesController {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    AppDelegateMockController *mock = [[AppDelegateMockController alloc] init];
    delegate.pdsController = (id)mock;

    [delegate stopServer:nil];
    XCTAssertEqual(mock.stopCalls, 1);
}

- (void)testApplicationWillTerminateStopsServer {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    AppDelegateMockController *mock = [[AppDelegateMockController alloc] init];
    delegate.pdsController = (id)mock;

    [delegate applicationWillTerminate:nil];
    XCTAssertEqual(mock.stopCalls, 1);
}

- (void)testApplicationDidFinishLaunchingInitializesControllerAndStartsServer {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    gStubStartReturn = YES;

    [delegate applicationDidFinishLaunching:nil];

    XCTAssertNotNil(delegate.pdsController);
    XCTAssertEqual(gStubStartCallCount, 1);
#if TARGET_OS_OSX || defined(__APPLE__)
    XCTAssertEqual(gStubSetupStatusBarCallCount, 1);
#endif
}

- (void)testApplicationDidFinishLaunchingStillSetsControllerWhenStartFails {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    gStubStartReturn = NO;

    [delegate applicationDidFinishLaunching:nil];

    XCTAssertNotNil(delegate.pdsController);
    XCTAssertEqual(gStubStartCallCount, 1);
#if TARGET_OS_OSX || defined(__APPLE__)
    XCTAssertEqual(gStubSetupStatusBarCallCount, 1);
#endif
}

@end

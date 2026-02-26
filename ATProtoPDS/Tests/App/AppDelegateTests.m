#import <XCTest/XCTest.h>
#import "App/AppDelegate.h"

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

@implementation AppDelegateTests

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

@end

#import <XCTest/XCTest.h>

#import "Network/HttpProtocolSession.h"

@interface HttpProtocolSessionTests : XCTestCase
@property(nonatomic, strong) HttpProtocolSession *session;
@end

@implementation HttpProtocolSessionTests

- (void)setUp {
  [super setUp];
  self.session = [[HttpProtocolSession alloc] init];
}

- (void)tearDown {
  self.session = nil;
  [super tearDown];
}

- (void)testFeedDataEmitsRequestReadyAndAllowsDispatch {
  NSData *requestData = [@"GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n"
      dataUsingEncoding:NSUTF8StringEncoding];
  NSArray<NSNumber *> *events = [self.session feedData:requestData];
  XCTAssertTrue([events containsObject:@(HttpSessionEventRequestReady)]);

  HttpRequest *request = [self.session nextRequestToDispatch];
  XCTAssertNotNil(request);
  XCTAssertEqualObjects(request.path, @"/test");
}

- (void)testUpgradeRequestIsExposedThroughFacade {
  NSData *requestData =
      [@"GET /xrpc/com.atproto.sync.subscribeRepos HTTP/1.1\r\n"
       @"Host: localhost\r\n"
       @"Connection: Upgrade\r\n"
       @"Upgrade: websocket\r\n\r\n"
          dataUsingEncoding:NSUTF8StringEncoding];
  NSArray<NSNumber *> *events = [self.session feedData:requestData];
  XCTAssertTrue([events containsObject:@(HttpSessionEventUpgrade)]);
  XCTAssertNotNil(self.session.currentUpgradeRequest);
}

- (void)testRemoteAddressIsOnlySetOnce {
  [self.session setRemoteAddressIfNeeded:@"10.0.0.1:1234"];
  [self.session setRemoteAddressIfNeeded:@"10.0.0.2:5678"];
  XCTAssertEqualObjects(self.session.parser.remoteAddress, @"10.0.0.1:1234");
}

- (void)testResponseDidFinishSendingUpdatesPipelineState {
  NSData *requestData =
      [@"GET /one HTTP/1.1\r\nHost: localhost\r\n\r\nGET /two HTTP/1.1\r\nHost: localhost\r\n\r\n"
          dataUsingEncoding:NSUTF8StringEncoding];
  [self.session feedData:requestData];
  XCTAssertGreaterThan(self.session.pendingDispatchCount, 0U);
  [self.session nextRequestToDispatch];
  [self.session responseDidFinishSending];
  XCTAssertTrue([self.session shouldReadMoreData]);
}

@end

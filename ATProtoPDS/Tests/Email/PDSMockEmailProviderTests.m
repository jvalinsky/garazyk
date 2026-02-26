#import <XCTest/XCTest.h>
#import "Email/PDSMockEmailProvider.h"

@interface PDSMockEmailProviderTests : XCTestCase
@property (nonatomic, strong) PDSMockEmailProvider *provider;
@end

@implementation PDSMockEmailProviderTests

- (void)setUp {
    [super setUp];
    self.provider = [[PDSMockEmailProvider alloc] init];
}

- (void)tearDown {
    self.provider = nil;
    [super tearDown];
}

- (void)testSendEmailRecordsMessage {
    NSError *error = nil;
    BOOL ok = [self.provider sendEmailTo:@"user@example.com"
                                 subject:@"Subject"
                                    body:@"Body"
                                   error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    XCTAssertEqual(self.provider.sentEmails.count, 1);
    XCTAssertEqualObjects(self.provider.lastSentEmail[@"to"], @"user@example.com");
    XCTAssertEqualObjects(self.provider.lastSentEmail[@"subject"], @"Subject");
    XCTAssertEqualObjects(self.provider.lastSentEmail[@"body"], @"Body");
}

- (void)testSendHtmlEmailRecordsHtmlAndText {
    NSError *error = nil;
    BOOL ok = [self.provider sendHtmlEmailTo:@"user@example.com"
                                     subject:@"HTML"
                                    htmlBody:@"<b>hi</b>"
                                    textBody:@"hi"
                                       error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    XCTAssertEqual(self.provider.sentEmails.count, 1);
    XCTAssertEqualObjects(self.provider.lastSentEmail[@"htmlBody"], @"<b>hi</b>");
    XCTAssertEqualObjects(self.provider.lastSentEmail[@"body"], @"hi");
}

- (void)testClearSentEmails {
    [self.provider sendEmailTo:@"a@example.com" subject:@"a" body:@"a" error:nil];
    [self.provider sendEmailTo:@"b@example.com" subject:@"b" body:@"b" error:nil];
    XCTAssertEqual(self.provider.sentEmails.count, 2);

    [self.provider clearSentEmails];
    XCTAssertEqual(self.provider.sentEmails.count, 0);
    XCTAssertNil(self.provider.lastSentEmail);
}

@end


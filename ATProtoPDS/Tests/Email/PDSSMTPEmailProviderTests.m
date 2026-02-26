#import <XCTest/XCTest.h>
#import "Email/PDSSMTPEmailProvider.h"

@interface PDSSMTPEmailProviderTests : XCTestCase
@end

@implementation PDSSMTPEmailProviderTests

- (void)testInitializationStoresConfiguration {
    PDSSMTPEmailProvider *provider = [[PDSSMTPEmailProvider alloc] initWithHost:@"smtp.example.com"
                                                                            port:587
                                                                        username:@"user"
                                                                        password:@"pass"
                                                                          useTLS:YES];
    XCTAssertEqualObjects(provider.smtpHost, @"smtp.example.com");
    XCTAssertEqual(provider.smtpPort, 587);
    XCTAssertEqualObjects(provider.username, @"user");
    XCTAssertEqualObjects(provider.password, @"pass");
    XCTAssertTrue(provider.useTLS);
}

- (void)testSendEmailReturnsSuccess {
    PDSSMTPEmailProvider *provider = [[PDSSMTPEmailProvider alloc] initWithHost:@"smtp.example.com"
                                                                            port:25
                                                                        username:nil
                                                                        password:nil
                                                                          useTLS:NO];
    NSError *error = nil;
    BOOL ok = [provider sendEmailTo:@"user@example.com" subject:@"Test" body:@"Body" error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
}

- (void)testSendHtmlEmailReturnsSuccess {
    PDSSMTPEmailProvider *provider = [[PDSSMTPEmailProvider alloc] initWithHost:@"smtp.example.com"
                                                                            port:25
                                                                        username:nil
                                                                        password:nil
                                                                          useTLS:NO];
    NSError *error = nil;
    BOOL ok = [provider sendHtmlEmailTo:@"user@example.com"
                                subject:@"Test"
                               htmlBody:@"<b>Body</b>"
                               textBody:@"Body"
                                  error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
}

@end


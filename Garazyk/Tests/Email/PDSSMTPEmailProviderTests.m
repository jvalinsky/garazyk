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

- (void)testSendEmailFailsClosed {
    PDSSMTPEmailProvider *provider = [[PDSSMTPEmailProvider alloc] initWithHost:@"smtp.example.com"
                                                                            port:25
                                                                        username:nil
                                                                        password:nil
                                                                          useTLS:NO];
    NSError *error = nil;
    BOOL ok = [provider sendEmailTo:@"user@example.com" subject:@"Test" body:@"Body" error:&error];
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSSMTPEmailProviderErrorDomain);
    XCTAssertEqual(error.code, PDSSMTPEmailProviderErrorNotImplemented);
}

- (void)testSendHtmlEmailFailsClosed {
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
    XCTAssertFalse(ok);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, PDSSMTPEmailProviderErrorDomain);
    XCTAssertEqual(error.code, PDSSMTPEmailProviderErrorNotImplemented);
}

- (void)testSendMethodsFailClosedWithNilErrorPointer {
    PDSSMTPEmailProvider *provider = [[PDSSMTPEmailProvider alloc] initWithHost:@"smtp.example.com"
                                                                            port:25
                                                                        username:nil
                                                                        password:nil
                                                                          useTLS:NO];

    XCTAssertFalse([provider sendEmailTo:@"user@example.com" subject:@"Test" body:@"Body" error:nil]);
    XCTAssertFalse([provider sendHtmlEmailTo:@"user@example.com"
                                     subject:@"Test"
                                    htmlBody:@"<b>Body</b>"
                                    textBody:@"Body"
                                       error:nil]);
}

@end

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Core/ATProtoServiceContainer.h"
#import "Email/PDSEmailProvider.h"
#import "Email/PDSMockEmailProvider.h"

@interface EmailIntegrationTests : XCTestCase

@property (nonatomic, strong) PDSController *controller;
@property (nonatomic, strong) NSString *dataDirectory;

@end

@implementation EmailIntegrationTests

- (void)setUp {
    [super setUp];
    
    // Create a temporary data directory
    self.dataDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.dataDirectory 
                            withIntermediateDirectories:YES 
                                             attributes:nil 
                                                  error:nil];

    // Configure the PDS for mock email. ATProtoServiceConfiguration.sharedConfiguration
    // is a process-wide singleton created once (dispatch_once) and never re-reads
    // env vars afterward, so by the time this test runs — after any earlier test
    // in the same AllTests process has already realized the singleton — setenv
    // here would have no effect on it. Build a standalone configuration instance
    // instead: its plain -init re-resolves PDS_EMAIL_PROVIDER fresh, and passing
    // it into PDSApplication explicitly bypasses the stale shared instance.
    setenv("PDS_EMAIL_PROVIDER", "mock", 1);

    ATProtoServiceConfiguration *config = [[ATProtoServiceConfiguration alloc] init];
    PDSApplication *application = [[PDSApplication alloc] initWithConfiguration:config
                                                                  dataDirectory:self.dataDirectory
                                                                 serviceMaxSize:10
                                                            userDatabaseMaxSize:100
                                                                didCacheMaxSize:1000
                                                              sequencerMaxSize:100];
    self.controller = application.legacyController ?: [[PDSController alloc] initWithApplication:application];
}

- (void)tearDown {
    [self.controller stopServer];
    [[NSFileManager defaultManager] removeItemAtPath:self.dataDirectory error:nil];
    unsetenv("PDS_EMAIL_PROVIDER");
    [super tearDown];
}

- (void)testEmailSentOnAccountCreation {
    NSError *error = nil;
    NSString *testEmail = @"test-email@example.com";
    NSString *testHandle = @"tester.test";
    
    NSDictionary *result = [self.controller createAccountForEmail:testEmail
                                                         password:@"password123"
                                                          handle:testHandle
                                                              did:nil
                                                            error:&error];
    
    XCTAssertNotNil(result, @"Account creation should succeed: %@", error);
    XCTAssertNil(error, @"Should be no error");
    
    // Verify that the email was sent
    // We need to get the email provider from the controller
    // PDSController doesn't expose accountService or emailProvider directly, 
    // but we can access it via the service container.
    
    id<PDSEmailProvider> emailProvider = [[ATProtoServiceContainer sharedContainer] resolveProtocol:@protocol(PDSEmailProvider)];
    XCTAssertNotNil(emailProvider, @"Email provider should be registered");
    XCTAssertTrue([emailProvider isKindOfClass:[PDSMockEmailProvider class]], @"Should use the mock provider");
    
    PDSMockEmailProvider *mockProvider = (PDSMockEmailProvider *)emailProvider;
    XCTAssertEqual(mockProvider.sentEmails.count, 1, @"One email should have been sent");
    
    NSDictionary *sentEmail = [mockProvider lastSentEmail];
    XCTAssertEqualObjects(sentEmail[@"to"], testEmail, @"Recipient should match");
    XCTAssertTrue([sentEmail[@"subject"] containsString:@"Welcome"], @"Subject should be a welcome email");
    XCTAssertTrue([sentEmail[@"body"] containsString:testHandle], @"Body should contain the handle");
}

@end

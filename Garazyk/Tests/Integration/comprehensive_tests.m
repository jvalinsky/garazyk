// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import "Core/DID.h"
#import "Identity/HandleResolver.h"
#import "Auth/OAuth2.h"

// Test utilities and helpers
@interface ATProtoPDSTests : XCTestCase

@property (nonatomic, strong) PDSController *pdsController;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) ATProtoDIDResolver *didResolver;
@property (nonatomic, strong) ATProtoHandleResolver *handleResolver;
@property (nonatomic, strong) ATProtoOAuth2Server *oauthServer;

@end

@implementation ATProtoPDSTests

- (void)setUp {
    [super setUp];

    // Initialize test database
    NSString *dbName = [NSString stringWithFormat:@"test-comprehensive-%@.sqlite", [[NSUUID UUID] UUIDString]];
    NSString *dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dbName];
    self.database = [[PDSDatabase alloc] initWithPath:dbPath];
    XCTAssertNotNil(self.database, @"Database should initialize");

    // Initialize resolvers
    self.didResolver = [[ATProtoDIDResolver alloc] init];
    self.handleResolver = [[ATProtoHandleResolver alloc] init];

    // Initialize OAuth server
    self.oauthServer = [[ATProtoOAuth2Server alloc] init];
    self.oauthServer.didResolver = self.didResolver;
    self.oauthServer.handleResolver = self.handleResolver;

    // Initialize PDS controller
    self.pdsController = [[PDSController alloc] initWithDatabase:self.database];
}

- (void)tearDown {
    [self.database close];
    [super tearDown];
}

@end
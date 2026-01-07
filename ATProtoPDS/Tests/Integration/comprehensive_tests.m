#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "PDSController.h"
#import "Database/PDSDatabase.h"
#import "DIDResolver.h"
#import "Identity/HandleResolver.h"
#import "OAuth2Server.h"

// Test utilities and helpers
@interface ATProtoPDSTests : XCTestCase

@property (nonatomic, strong) PDSController *pdsController;
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) DIDResolver *didResolver;
@property (nonatomic, strong) HandleResolver *handleResolver;
@property (nonatomic, strong) OAuth2Server *oauthServer;

@end

@implementation ATProtoPDSTests

- (void)setUp {
    [super setUp];

    // Initialize test database
    self.database = [[PDSDatabase alloc] initWithPath:@":memory:"];
    XCTAssertNotNil(self.database, @"Database should initialize");

    // Initialize resolvers
    self.didResolver = [[DIDResolver alloc] init];
    self.handleResolver = [[HandleResolver alloc] init];

    // Initialize OAuth server
    self.oauthServer = [[OAuth2Server alloc] init];
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
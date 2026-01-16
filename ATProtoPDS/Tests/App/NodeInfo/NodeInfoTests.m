#import <XCTest/XCTest.h>
#import "App/NodeInfo/NodeInfoProvider.h"
#import "App/NodeInfo/NodeInfoHandler.h"
#import "App/NodeInfo/NodeInfoSchemas.h"
#import "App/PDSConfiguration.h"

@interface NodeInfoTests : XCTestCase
@end

@implementation NodeInfoTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testProviderInitialization {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    XCTAssertNotNil(config);

    NSString *baseURL = @"https://pds.example.com";
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:baseURL configuration:config];

    XCTAssertNotNil(provider);
    XCTAssertNotNil(provider.nodeInfo20);
    XCTAssertNotNil(provider.nodeInfo21);
}

- (void)testProviderVersionFields {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo20 = provider.nodeInfo20;
    XCTAssertEqualObjects(nodeInfo20[@"version"], @"2.0");

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    XCTAssertEqualObjects(nodeInfo21[@"version"], @"2.1");
}

- (void)testProviderSoftwareFields {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSDictionary *software = nodeInfo21[@"software"];
    XCTAssertNotNil(software);
    XCTAssertNotNil(software[@"name"]);
    XCTAssertNotNil(software[@"version"]);
}

- (void)testProviderProtocolsField {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSArray *protocols = nodeInfo21[@"protocols"];
    XCTAssertNotNil(protocols);
    XCTAssertTrue([protocols containsObject:NodeInfoProtocolAtproto]);
}

- (void)testProviderServicesField {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSDictionary *services = nodeInfo21[@"services"];
    XCTAssertNotNil(services);
    XCTAssertNotNil(services[@"inbound"]);
    XCTAssertNotNil(services[@"outbound"]);
}

- (void)testProviderOpenRegistrations {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    XCTAssertNotNil(nodeInfo21[@"openRegistrations"]);
}

- (void)testProviderUsageField {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSDictionary *usage = nodeInfo21[@"usage"];
    XCTAssertNotNil(usage);

    NSDictionary *users = usage[@"users"];
    XCTAssertNotNil(users);
    XCTAssertNotNil(users[@"total"]);
    XCTAssertNotNil(users[@"activeMonth"]);
    XCTAssertNotNil(users[@"activeHalfyear"]);
}

- (void)testProviderMetadataField {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    XCTAssertNotNil(nodeInfo21[@"metadata"]);
}

- (void)testProviderDiscoveryDocument {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *discovery21 = provider.discoveryDocument21;
    XCTAssertNotNil(discovery21);
    XCTAssertNotNil(discovery21[@"links"]);
    XCTAssertTrue([discovery21[@"links"] isKindOfClass:[NSArray class]]);
    XCTAssertTrue([discovery21[@"links"] count] > 0);

    NSDictionary *firstLink = discovery21[@"links"][0];
    XCTAssertEqualObjects(firstLink[@"rel"], NodeInfoSchemaRel21);
    XCTAssertNotNil(firstLink[@"href"]);
}

- (void)testProviderInvalidBaseURL {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];

    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:nil configuration:config]);
    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:@"" configuration:config]);
    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:@"not-a-url" configuration:config]);
}

- (void)testProviderNilConfiguration {
    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:nil]);
}

- (void)testSchemaConstants {
    XCTAssertNotNil(NodeInfoSchemaRel20);
    XCTAssertNotNil(NodeInfoSchemaRel21);
    XCTAssertNotNil(NodeInfoSchemaProfile20);
    XCTAssertNotNil(NodeInfoSchemaProfile21);
    XCTAssertNotNil(NodeInfoVersion20);
    XCTAssertNotNil(NodeInfoVersion21);
    XCTAssertNotNil(NodeInfoProtocolAtproto);
}

- (void)testHandlerSingleton {
    NodeInfoHandler *handler1 = [NodeInfoHandler sharedHandler];
    NodeInfoHandler *handler2 = [NodeInfoHandler sharedHandler];
    XCTAssertEqualObjects(handler1, handler2);
}

@end

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/NodeInfo/NodeInfoProvider.h"
#import "App/NodeInfo/NodeInfoHandler.h"
#import "App/NodeInfo/NodeInfoSchemas.h"
#import "App/ATProtoServiceConfiguration.h"

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
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    XCTAssertNotNil(config);

    NSString *baseURL = @"https://pds.example.com";
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:baseURL configuration:config];

    XCTAssertNotNil(provider);
    XCTAssertTrue([provider.nodeInfo20 isKindOfClass:[NSDictionary class]]);
    XCTAssertTrue([provider.nodeInfo21 isKindOfClass:[NSDictionary class]]);
}

- (void)testProviderVersionFieldsMatchExpected {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo20 = provider.nodeInfo20;
    XCTAssertEqualObjects(nodeInfo20[@"version"], @"2.0");

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    XCTAssertEqualObjects(nodeInfo21[@"version"], @"2.1");
}

- (void)testProviderSoftwareFields {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSDictionary *software = nodeInfo21[@"software"];
    XCTAssertNotNil(software);
    XCTAssertTrue([software[@"name"] isKindOfClass:[NSString class]]);
    XCTAssertTrue([software[@"version"] isKindOfClass:[NSString class]]);
}

- (void)testProviderProtocolsFieldContainsAtproto {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSArray *protocols = nodeInfo21[@"protocols"];
    XCTAssertNotNil(protocols);
    XCTAssertTrue([protocols containsObject:NodeInfoProtocolAtproto]);
}

- (void)testProviderServicesField {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSDictionary *services = nodeInfo21[@"services"];
    XCTAssertNotNil(services);
    XCTAssertTrue([services[@"inbound"] isKindOfClass:[NSArray class]]);
    XCTAssertTrue([services[@"outbound"] isKindOfClass:[NSArray class]]);
}

- (void)testProviderOpenRegistrations {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    XCTAssertTrue([nodeInfo21[@"openRegistrations"] isKindOfClass:[NSNumber class]]);
}

- (void)testProviderUsageField {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    NSDictionary *usage = nodeInfo21[@"usage"];
    XCTAssertNotNil(usage);

    NSDictionary *users = usage[@"users"];
    XCTAssertNotNil(users);
    XCTAssertTrue([users[@"total"] isKindOfClass:[NSNumber class]]);
    XCTAssertTrue([users[@"activeMonth"] isKindOfClass:[NSNumber class]]);
    XCTAssertTrue([users[@"activeHalfyear"] isKindOfClass:[NSNumber class]]);
}

- (void)testProviderMetadataField {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NodeInfoProvider *provider = [[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:config];

    NSDictionary *nodeInfo21 = provider.nodeInfo21;
    XCTAssertTrue([nodeInfo21[@"metadata"] isKindOfClass:[NSDictionary class]]);
}

- (void)testProviderDiscoveryDocument {
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
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
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];

    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:nil configuration:config]);
    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:@"" configuration:config]);
    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:@"not-a-url" configuration:config]);
}

- (void)testProviderNilConfiguration {
    XCTAssertNil([[NodeInfoProvider alloc] initWithBaseURL:@"https://pds.example.com" configuration:nil]);
}

- (void)testSchemaConstants {
    XCTAssertTrue([NodeInfoSchemaRel20 isKindOfClass:[NSString class]]);
    XCTAssertTrue([NodeInfoSchemaRel21 isKindOfClass:[NSString class]]);
    XCTAssertTrue([NodeInfoSchemaProfile20 isKindOfClass:[NSString class]]);
    XCTAssertTrue([NodeInfoSchemaProfile21 isKindOfClass:[NSString class]]);
    XCTAssertTrue([NodeInfoVersion20 isKindOfClass:[NSString class]]);
    XCTAssertTrue([NodeInfoVersion21 isKindOfClass:[NSString class]]);
    XCTAssertTrue([NodeInfoProtocolAtproto isKindOfClass:[NSString class]]);
}

- (void)testHandlerSingleton {
    NodeInfoHandler *handler1 = [NodeInfoHandler sharedHandler];
    NodeInfoHandler *handler2 = [NodeInfoHandler sharedHandler];
    XCTAssertEqualObjects(handler1, handler2);
}

@end

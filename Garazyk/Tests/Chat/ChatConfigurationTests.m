// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Chat/Server/Config/ChatConfiguration.h"

@interface ChatConfigurationTests : XCTestCase
@end

@implementation ChatConfigurationTests

- (void)testDefaultConfiguration {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    XCTAssertNotNil(config);
    XCTAssertEqual(config.httpPort, 2585);
    XCTAssertEqualObjects(config.dataDirectory, @"./data/chat");
    XCTAssertNil(config.serviceDomain);
}

- (void)testServiceDIDDefaultsToLocalhostWithPort {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    config.httpPort = 2585;
    config.serviceDomain = nil;
    XCTAssertEqualObjects(config.serviceDID, @"did:web:localhost%3A2585");
}

- (void)testServiceDIDUsesExplicitDomain {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    config.serviceDomain = @"chat.garazyk.xyz";
    XCTAssertEqualObjects(config.serviceDID, @"did:web:chat.garazyk.xyz");
}

- (void)testServiceDIDWithStandardPortProducesPlainDomain {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    config.serviceDomain = @"chat.garazyk.xyz:443";
    XCTAssertEqualObjects(config.serviceDID, @"did:web:chat.garazyk.xyz");
}

- (void)testServiceDIDWithNonStandardPortEncodesPort {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    config.serviceDomain = @"chat.garazyk.xyz:8443";
    XCTAssertEqualObjects(config.serviceDID, @"did:web:chat.garazyk.xyz%3A8443");
}

- (void)testServiceDIDWithLocalhostAndPort {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    config.serviceDomain = @"localhost:2585";
    XCTAssertEqualObjects(config.serviceDID, @"did:web:localhost%3A2585");
}

- (void)testServiceDIDWithIPAddress {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    config.serviceDomain = @"192.168.1.100";
    XCTAssertEqualObjects(config.serviceDID, @"did:web:192.168.1.100");
}

- (void)testServiceDIDWithIPAddressAndPort {
    ChatConfiguration *config = [ChatConfiguration defaultConfiguration];
    config.serviceDomain = @"192.168.1.100:9090";
    XCTAssertEqualObjects(config.serviceDID, @"did:web:192.168.1.100%3A9090");
}

@end

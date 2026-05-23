// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZProviderRegistryTests.m

 @abstract Tests for the central provider registry.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "Core/GZProviderRegistry.h"
#import "Core/GZProviderHTTPClient.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Email/PDSEmailProviderFactory.h"

#pragma mark - Mock Provider Factory

@interface GZTestProviderFactory : NSObject <GZProviderFactory>
+ (NSArray<NSString *> *)supportedIdentifiers;
+ (nullable id)providerWithIdentifier:(NSString *)identifier
                         configuration:(ATProtoServiceConfiguration *)configuration
                        secretsProvider:(nullable id)secretsProvider
                                  error:(NSError **)error;
@end

@implementation GZTestProviderFactory

+ (NSArray<NSString *> *)supportedIdentifiers {
    return @[@"test_provider"];
}

+ (nullable id)providerWithIdentifier:(NSString *)identifier
                         configuration:(ATProtoServiceConfiguration *)configuration
                        secretsProvider:(nullable id)secretsProvider
                                  error:(NSError **)error {
    if ([identifier isEqualToString:@"test_provider"]) {
        return [[NSObject alloc] init];
    }
    if (error) {
        *error = [NSError errorWithDomain:@"GZTestProviderFactoryErrorDomain"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unknown provider"}];
    }
    return nil;
}

@end

#pragma mark - Tests

@interface GZProviderRegistryTests : XCTestCase
@end

@implementation GZProviderRegistryTests

- (void)tearDown {
    [[GZProviderRegistry sharedRegistry] reset];
    [super tearDown];
}

- (void)testSharedRegistryReturnsSingleton {
    GZProviderRegistry *a = [GZProviderRegistry sharedRegistry];
    GZProviderRegistry *b = [GZProviderRegistry sharedRegistry];
    XCTAssertEqual(a, b);
}

- (void)testRegisterFactoryForProtocol {
    Protocol *testProtocol = @protocol(GZProviderFactory);
    [[GZProviderRegistry sharedRegistry] registerFactory:[GZTestProviderFactory class]
                                              forProtocol:testProtocol];

    NSArray *identifiers = [[GZProviderRegistry sharedRegistry] identifiersForProtocol:testProtocol];
    XCTAssertEqualObjects(identifiers, (@[@"test_provider"]));
}

- (void)testUnregisterFactoryForProtocol {
    Protocol *testProtocol = @protocol(GZProviderFactory);
    [[GZProviderRegistry sharedRegistry] registerFactory:[GZTestProviderFactory class]
                                              forProtocol:testProtocol];
    [[GZProviderRegistry sharedRegistry] unregisterFactoryForProtocol:testProtocol];

    NSArray *identifiers = [[GZProviderRegistry sharedRegistry] identifiersForProtocol:testProtocol];
    XCTAssertEqual(identifiers.count, 0);
}

- (void)testResolveProviderForProtocol {
    Protocol *testProtocol = @protocol(GZProviderFactory);
    [[GZProviderRegistry sharedRegistry] registerFactory:[GZTestProviderFactory class]
                                              forProtocol:testProtocol];

    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSError *error = nil;
    id provider = [[GZProviderRegistry sharedRegistry] resolveProviderForProtocol:testProtocol
                                                                       identifier:@"test_provider"
                                                                    configuration:config
                                                                   secretsProvider:nil
                                                                             error:&error];
    XCTAssertNotNil(provider);
    XCTAssertNil(error);
}

- (void)testResolveProviderReturnsNilForUnknownProtocol {
    Protocol *unknownProtocol = @protocol(NSObject);
    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSError *error = nil;
    id provider = [[GZProviderRegistry sharedRegistry] resolveProviderForProtocol:unknownProtocol
                                                                       identifier:@"test"
                                                                    configuration:config
                                                                   secretsProvider:nil
                                                                             error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testResolveProviderReturnsNilForUnsupportedIdentifier {
    Protocol *testProtocol = @protocol(GZProviderFactory);
    [[GZProviderRegistry sharedRegistry] registerFactory:[GZTestProviderFactory class]
                                              forProtocol:testProtocol];

    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSError *error = nil;
    id provider = [[GZProviderRegistry sharedRegistry] resolveProviderForProtocol:testProtocol
                                                                       identifier:@"nonexistent"
                                                                    configuration:config
                                                                   secretsProvider:nil
                                                                             error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testResetClearsAllRegistrations {
    Protocol *testProtocol = @protocol(GZProviderFactory);
    [[GZProviderRegistry sharedRegistry] registerFactory:[GZTestProviderFactory class]
                                              forProtocol:testProtocol];
    [[GZProviderRegistry sharedRegistry] reset];

    NSArray *identifiers = [[GZProviderRegistry sharedRegistry] identifiersForProtocol:testProtocol];
    XCTAssertEqual(identifiers.count, 0);
}

@end

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSProviderRegistryTests.m

 @abstract Tests for the central provider registry.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "Core/PDSProviderRegistry.h"
#import "Core/PDSProviderHTTPClient.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Email/PDSEmailProviderFactory.h"

#pragma mark - Mock Provider Factory

@interface PDSTestProviderFactory : NSObject <PDSProviderFactory>
+ (NSArray<NSString *> *)supportedIdentifiers;
+ (nullable id)providerWithIdentifier:(NSString *)identifier
                         configuration:(ATProtoServiceConfiguration *)configuration
                        secretsProvider:(nullable id)secretsProvider
                                  error:(NSError **)error;
@end

@implementation PDSTestProviderFactory

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
        *error = [NSError errorWithDomain:@"PDSTestProviderFactoryErrorDomain"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unknown provider"}];
    }
    return nil;
}

@end

#pragma mark - Tests

@interface PDSProviderRegistryTests : XCTestCase
@end

@implementation PDSProviderRegistryTests

- (void)tearDown {
    [[PDSProviderRegistry sharedRegistry] reset];
    [super tearDown];
}

- (void)testSharedRegistryReturnsSingleton {
    PDSProviderRegistry *a = [PDSProviderRegistry sharedRegistry];
    PDSProviderRegistry *b = [PDSProviderRegistry sharedRegistry];
    XCTAssertEqual(a, b);
}

- (void)testRegisterFactoryForProtocol {
    Protocol *testProtocol = @protocol(PDSProviderFactory);
    [[PDSProviderRegistry sharedRegistry] registerFactory:[PDSTestProviderFactory class]
                                              forProtocol:testProtocol];

    NSArray *identifiers = [[PDSProviderRegistry sharedRegistry] identifiersForProtocol:testProtocol];
    XCTAssertEqualObjects(identifiers, (@[@"test_provider"]));
}

- (void)testUnregisterFactoryForProtocol {
    Protocol *testProtocol = @protocol(PDSProviderFactory);
    [[PDSProviderRegistry sharedRegistry] registerFactory:[PDSTestProviderFactory class]
                                              forProtocol:testProtocol];
    [[PDSProviderRegistry sharedRegistry] unregisterFactoryForProtocol:testProtocol];

    NSArray *identifiers = [[PDSProviderRegistry sharedRegistry] identifiersForProtocol:testProtocol];
    XCTAssertEqual(identifiers.count, 0);
}

- (void)testResolveProviderForProtocol {
    Protocol *testProtocol = @protocol(PDSProviderFactory);
    [[PDSProviderRegistry sharedRegistry] registerFactory:[PDSTestProviderFactory class]
                                              forProtocol:testProtocol];

    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSError *error = nil;
    id provider = [[PDSProviderRegistry sharedRegistry] resolveProviderForProtocol:testProtocol
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
    id provider = [[PDSProviderRegistry sharedRegistry] resolveProviderForProtocol:unknownProtocol
                                                                       identifier:@"test"
                                                                    configuration:config
                                                                   secretsProvider:nil
                                                                             error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testResolveProviderReturnsNilForUnsupportedIdentifier {
    Protocol *testProtocol = @protocol(PDSProviderFactory);
    [[PDSProviderRegistry sharedRegistry] registerFactory:[PDSTestProviderFactory class]
                                              forProtocol:testProtocol];

    ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
    NSError *error = nil;
    id provider = [[PDSProviderRegistry sharedRegistry] resolveProviderForProtocol:testProtocol
                                                                       identifier:@"nonexistent"
                                                                    configuration:config
                                                                   secretsProvider:nil
                                                                             error:&error];
    XCTAssertNil(provider);
    XCTAssertNotNil(error);
}

- (void)testResetClearsAllRegistrations {
    Protocol *testProtocol = @protocol(PDSProviderFactory);
    [[PDSProviderRegistry sharedRegistry] registerFactory:[PDSTestProviderFactory class]
                                              forProtocol:testProtocol];
    [[PDSProviderRegistry sharedRegistry] reset];

    NSArray *identifiers = [[PDSProviderRegistry sharedRegistry] identifiersForProtocol:testProtocol];
    XCTAssertEqual(identifiers.count, 0);
}

@end

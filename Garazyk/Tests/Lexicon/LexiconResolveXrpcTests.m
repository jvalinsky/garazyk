// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcHandler.h"

@interface LexiconResolveXrpcTests : XCTestCase
@end

static HttpResponse *xrpcDispatchRequest(XrpcDispatcher *dispatcher,
                                         NSString *path,
                                         NSDictionary<NSString *, NSString *> *headers) {
    HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                   methodString:@"GET"
                                                           path:path
                                                    queryString:@""
                                                    queryParams:@{}
                                                        version:@"1.1"
                                                        headers:headers ?: @{}
                                                           body:[NSData data]
                                                   remoteAddress:@"127.0.0.1"];
    HttpResponse *response = [HttpResponse response];
    [dispatcher handleRequest:request response:response];
    return response;
}

@implementation LexiconResolveXrpcTests

- (void)testAllRegisteredMethodsCanBeResolved {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        // Get all registered method IDs from the dispatcher's methodHandlers dictionary
        // We need to access the private property, so we'll use KVC or test via reflection
        NSMutableDictionary<NSString *, XrpcMethodHandler> *methodHandlers =
            [dispatcher valueForKey:@"methodHandlers"];

        XCTAssertNotNil(methodHandlers, @"Dispatcher should have methodHandlers");
        XCTAssertGreaterThan(methodHandlers.count, 0, @"Should have registered methods");

        NSMutableArray<NSString *> *failedMethods = [NSMutableArray array];
        NSMutableArray<NSString *> *notFoundMethods = [NSMutableArray array];
        NSMutableArray<NSString *> *notImplementedMethods = [NSMutableArray array];

        NSLog(@"Testing resolution of %lu registered XRPC methods", (unsigned long)methodHandlers.count);

        for (NSString *methodId in methodHandlers.allKeys) {
            // Skip internal/non-standard methods (starting with _) as they don't have lexicons
            if ([methodId hasPrefix:@"_"]) {
                NSLog(@"Skipping internal method: %@", methodId);
                continue;
            }

            NSString *path = [NSString stringWithFormat:@"/xrpc/com.atproto.lexicon.resolveLexicon?def=%@",
                             [methodId stringByAddingPercentEncodingWithAllowedCharacters:
                              [NSCharacterSet URLQueryAllowedCharacterSet]]];

            HttpResponse *response = xrpcDispatchRequest(dispatcher, path, @{@"host": @"localhost:2583"});

            // Verify HTTP 200 OK (not 404 or 501)
            if (response.statusCode == HttpStatusNotFound) {
                [notFoundMethods addObject:methodId];
                NSLog(@"FAIL: %@ returned 404 Not Found", methodId);
            } else if (response.statusCode == HttpStatusNotImplemented) {
                [notImplementedMethods addObject:methodId];
                NSLog(@"FAIL: %@ returned 501 Not Implemented", methodId);
            } else if (response.statusCode != HttpStatusOK) {
                [failedMethods addObject:[NSString stringWithFormat:@"%@ (%lu)", methodId,
                                                                    (unsigned long)response.statusCode]];
                NSLog(@"FAIL: %@ returned %lu", methodId, (unsigned long)response.statusCode);
            } else {
                // Verify response structure
                NSDictionary *jsonBody = response.jsonBody;
                XCTAssertTrue([jsonBody isKindOfClass:[NSDictionary class]],
                             @"Response for %@ should be a dictionary", methodId);

                // Verify lexiconDoc field exists
                NSDictionary *lexiconDoc = jsonBody[@"lexiconDoc"];
                if (!lexiconDoc) {
                    [failedMethods addObject:[NSString stringWithFormat:@"%@ (missing lexiconDoc)", methodId]];
                    NSLog(@"FAIL: %@ response missing lexiconDoc", methodId);
                    continue;
                }

                // Verify lexiconDoc.id matches the requested method_id
                NSString *docId = lexiconDoc[@"id"];
                if (![docId isEqualToString:methodId]) {
                    [failedMethods addObject:[NSString stringWithFormat:@"%@ (id mismatch: got %@)", methodId, docId]];
                    NSLog(@"FAIL: %@ has mismatched id in lexiconDoc", methodId);
                    continue;
                }

                // Verify proxied field is a boolean
                id proxied = jsonBody[@"proxied"];
                if (proxied && ![proxied isKindOfClass:[NSNumber class]]) {
                    [failedMethods addObject:[NSString stringWithFormat:@"%@ (proxied not boolean)", methodId]];
                    NSLog(@"FAIL: %@ proxied field is not a boolean", methodId);
                    continue;
                }

                NSLog(@"PASS: %@ resolved successfully (proxied=%@)", methodId, proxied ?: @"null");
            }
        }

        // Assert that zero methods returned 404
        XCTAssertEqual(notFoundMethods.count, 0,
                      @"No methods should return 404. Failed methods: %@", notFoundMethods);

        // Assert that zero methods returned 501
        XCTAssertEqual(notImplementedMethods.count, 0,
                      @"No methods should return 501. Failed methods: %@", notImplementedMethods);

        // Assert that all other methods resolved successfully
        XCTAssertEqual(failedMethods.count, 0,
                      @"All methods should resolve successfully. Failed methods: %@", failedMethods);

        NSLog(@"SUCCESS: All %lu registered methods resolved without 404 or 501",
              (unsigned long)methodHandlers.count);

    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testResolveLexiconReturnsValidStructure {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        NSString *path = @"/xrpc/com.atproto.lexicon.resolveLexicon?def=com.atproto.server.describeServer";
        HttpResponse *response = xrpcDispatchRequest(dispatcher, path, @{@"host": @"localhost:2583"});

        XCTAssertEqual(response.statusCode, HttpStatusOK,
                      @"resolveLexicon should return 200 OK");

        NSDictionary *jsonBody = response.jsonBody;
        XCTAssertTrue([jsonBody isKindOfClass:[NSDictionary class]],
                     @"Response should be a dictionary");

        // Must have lexiconDoc field
        NSDictionary *lexiconDoc = jsonBody[@"lexiconDoc"];
        XCTAssertNotNil(lexiconDoc,
                       @"Response must include lexiconDoc field");

        // lexiconDoc must have id field matching request
        NSString *docId = lexiconDoc[@"id"];
        XCTAssertEqualObjects(docId, @"com.atproto.server.describeServer",
                             @"lexiconDoc.id must match requested method");

        // proxied field should be a boolean (or null)
        id proxied = jsonBody[@"proxied"];
        if (proxied) {
            XCTAssertTrue([proxied isKindOfClass:[NSNumber class]],
                         @"proxied field must be a boolean");
        }
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testResolveLexiconForLocalVsProxiedMethods {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        // Test a few representative methods from different namespaces
        NSArray<NSString *> *testMethods = @[
            @"com.atproto.server.describeServer",  // Local
            @"com.atproto.identity.resolveHandle",  // Local
            @"com.atproto.repo.describeRepo",       // Local
            @"com.atproto.sync.getLatestCommit",   // Local
            @"app.bsky.actor.getProfile",           // May be proxied or local
        ];

        for (NSString *methodId in testMethods) {
            NSString *path = [NSString stringWithFormat:@"/xrpc/com.atproto.lexicon.resolveLexicon?def=%@",
                             [methodId stringByAddingPercentEncodingWithAllowedCharacters:
                              [NSCharacterSet URLQueryAllowedCharacterSet]]];

            HttpResponse *response = xrpcDispatchRequest(dispatcher, path, @{@"host": @"localhost:2583"});

            XCTAssertEqual(response.statusCode, HttpStatusOK,
                          @"Method %@ should resolve with 200 OK", methodId);

            NSDictionary *jsonBody = response.jsonBody;
            NSDictionary *lexiconDoc = jsonBody[@"lexiconDoc"];
            XCTAssertNotNil(lexiconDoc,
                           @"Method %@ should have lexiconDoc", methodId);

            NSString *docId = lexiconDoc[@"id"];
            XCTAssertEqualObjects(docId, methodId,
                                 @"Method %@ lexiconDoc.id should match", methodId);

            id proxied = jsonBody[@"proxied"];
            NSLog(@"Method %@ resolved: proxied=%@", methodId, proxied ?: @"null");
        }
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

- (void)testUnknownMethodReturnsError {
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tempURL withIntermediateDirectories:YES attributes:nil error:nil];

    @try {
        PDSApplication *app = [[PDSApplication alloc] initWithDataDirectory:tempURL.path];
        XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
        [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher application:app];

        NSString *path = @"/xrpc/com.atproto.lexicon.resolveLexicon?def=com.atproto.nonexistent.method";
        HttpResponse *response = xrpcDispatchRequest(dispatcher, path, @{@"host": @"localhost:2583"});

        // Unknown methods should not resolve
        XCTAssertNotEqual(response.statusCode, HttpStatusOK,
                         @"Unknown method should not return 200");

        NSDictionary *jsonBody = response.jsonBody;
        XCTAssertTrue([jsonBody isKindOfClass:[NSDictionary class]],
                     @"Error response should be a dictionary");
        XCTAssertNotNil(jsonBody[@"error"],
                       @"Error response should have error field");
    } @finally {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    }
}

@end

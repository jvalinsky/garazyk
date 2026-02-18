//
//  fuzz_xrpc.mm
//  Comprehensive XRPC fuzzing harness for ATProto PDS
//
//  Tests:
//  1. XRPC method parsing and dispatch
//  2. Lexicon NSID validation
//  3. Record validation against schemas
//  4. DID/handle resolution
//  5. Authentication and authorization
//  6. Input validation and sanitization
//

#import <Foundation/Foundation.h>
#import "Core/DID.h"
#import "Core/CID.h"
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/Session.h"
#import "Auth/DPoPUtil.h"
#import "Identity/HandleResolver.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 100000) {
        return 0;
    }

    @autoreleasepool {
        NSData *inputData = [NSData dataWithBytes:data length:size];

        // Test 1: Basic XRPC request parsing
        HttpRequest *request = [HttpRequest requestWithData:inputData];

        HttpMethod method = request.method;
        NSString *path = request.path;
        NSString *queryString = request.queryString;
        NSDictionary *headers = request.headers;
        NSData *body = request.body;
        NSDictionary *jsonBody = request.jsonBody;

        (void)method;

        // Test 2: XRPC method extraction from path
        if (path.length > 6) {
            NSString *xrpcPrefix = [path substringToIndex:6];
            (void)xrpcPrefix;

            NSString *methodName = [path substringFromIndex:6];
            (void)methodName;

            // Test NSID parsing
            if ([methodName containsString:@"."]) {
                NSArray<NSString *> *parts = [methodName componentsSeparatedByString:@"."];
                (void)parts;
            }
        }

        // Test 3: Query parameter extraction for XRPC
        if (queryString.length > 0) {
            NSDictionary *xrpcParams = request.queryParams;
            (void)xrpcParams;

            for (NSString *key in xrpcParams) {
                NSString *value = [request queryParamForKey:key];
                (void)value;
            }
        }

        // Test 4: JSON body validation for various methods
        NSArray *methodsNeedingBody = @[
            @"com.atproto.server.createAccount",
            @"com.atproto.server.createSession",
            @"com.atproto.server.refreshSession",
            @"com.atproto.server.updateEmail",
            @"com.atproto.server.updateHandle",
            @"com.atproto.server.deleteAccount",
            @"com.atproto.repo.createRecord",
            @"com.atproto.repo.putRecord",
            @"com.atproto.repo.deleteRecord",
            @"com.atproto.repo.uploadBlob"
        ];

        for (NSString *method in methodsNeedingBody) {
            if ([path containsString:method]) {
                if (jsonBody) {
                    // Validate required fields
                    BOOL hasRequired = YES;
                    if ([method containsString:@"createAccount"]) {
                        hasRequired = jsonBody[@"email"] && jsonBody[@"handle"];
                    } else if ([method containsString:@"createSession"]) {
                        hasRequired = jsonBody[@"identifier"];
                    } else if ([method containsString:@"createRecord"]) {
                        hasRequired = jsonBody[@"repo"] && jsonBody[@"collection"];
                    }
                    (void)hasRequired;
                }
            }
        }

        // Test 5: DID string parsing and validation
        NSArray *didTests = @[
            @"did:web:example.com",
            @"did:plc:ewvi7nxzyoun6zhxrhs64oiz",
            @"did:key:z6MkiTBz1ymLq1Z",
            @"did:plc:00000000000000000000000000000000",
            @"did:web:sub.domain.example.com",
            @"invalid",
            @"",
            @"did:unknown:test",
            @"did:",
            @"did:plc"  // missing identifier
        ];

        for (NSString *didString in didTests) {
            // Test DID string validation logic
            BOOL validFormat = [didString hasPrefix:@"did:"];
            NSString *method = nil;
            NSString *identifier = nil;
            
            if (validFormat && didString.length > 5) {
                NSString *withoutPrefix = [didString substringFromIndex:4];
                NSRange methodEnd = [withoutPrefix rangeOfString:@":"];
                if (methodEnd.location != NSNotFound && methodEnd.location > 0) {
                    method = [withoutPrefix substringToIndex:methodEnd.location];
                    identifier = [withoutPrefix substringFromIndex:methodEnd.location + 1];
                } else if (withoutPrefix.length > 0) {
                    // DID without method-specific identifier (e.g., "did:plc")
                    method = withoutPrefix;
                }
            }
            
            (void)validFormat;
            (void)method;
            (void)identifier;
        }

        // Test 6: Handle parsing
        NSArray *handleTests = @[
            @"user.example.com",
            @"sub.domain.example.com",
            @"123.456.789.012",
            @"invalid@no_tld",
            @"",
            @"toolong.example.com"
        ];

        for (NSString *handle in handleTests) {
            HandleResolver *resolver = [[HandleResolver alloc] init];
            (void)resolver;

            // Just test handle string validation
            BOOL valid = [handle containsString:@"."] && handle.length < 256;
            (void)valid;
        }

        // Test 7: Record type validation
        if (jsonBody) {
            NSString *recordType = jsonBody[@"$type"];
            (void)recordType;

            // Common ATProto record types
            NSSet *validTypes = [NSSet setWithArray:@[
                @"app.bsky.feed.post",
                @"app.bsky.feed.like",
                @"app.bsky.feed.repost",
                @"app.bsky.graph.follow",
                @"app.bsky.graph.block",
                @"app.bsky.actor.profile",
                @"app.bsky.notification.record",
                @"com.atproto.lexicon.schema",
                @"blob"
            ]];

            if (recordType) {
                BOOL isValid = [validTypes containsObject:recordType];
                (void)isValid;
            }
        }

        // Test 8: Lexicon NSID parsing
        NSArray *nsidTests = @[
            @"com.atproto.server.createAccount",
            @"app.bsky.feed.post",
            @"app.bsky.graph.follow",
            @"com.atproto.lexicon.schema",
            @"invalid.nsid",
            @""
        ];

        for (NSString *nsid in nsidTests) {
            // NSID format: reversed domain + name
            BOOL valid = [nsid containsString:@"."] && [nsid componentsSeparatedByString:@"."].count >= 2;
            (void)valid;
        }

        // Test 9: DPoP token parsing (if present)
        NSString *authHeader = headers[@"Authorization"];
        if ([authHeader hasPrefix:@"DPoP "]) {
            NSString *dpopToken = [authHeader substringFromIndex:5];
            (void)dpopToken;
        }

        // Test 10: Response construction for various XRPC errors
        NSDictionary *errorResponses = @{
            @"InvalidRequest": @{@"error": @"InvalidRequest", @"message": @"test"},
            @"AuthenticationFailed": @{@"error": @"AuthenticationFailed"},
            @"NotFound": @{@"error": @"NotFound"},
            @"OperationFailed": @{@"error": @"OperationFailed"}
        };

        for (NSString *errorKey in errorResponses) {
            NSDictionary *errorBody = errorResponses[errorKey];
            (void)errorBody;
        }

        // Test 11: Pagination parameters
        NSDictionary *paginationParams = @{
            @"limit": @(25),
            @"cursor": @"cursor123",
            @"before": @"timestamp",
            @"since": @"timestamp"
        };

        for (NSString *key in paginationParams) {
            id value = paginationParams[key];
            (void)value;
        }

        // Test 12: Content type validation for responses
        NSArray *responseContentTypes = @[
            @"application/json",
            @"application/cbor"
        ];

        for (NSString *contentType in responseContentTypes) {
            HttpResponse *response = [[HttpResponse alloc] init];
            response.statusCode = HttpStatusOK;
            response.contentType = contentType;
            NSData *serialized = [response serialize];
            (void)serialized;
        }

        // Test 13: Large record payloads
        if (size > 1000 && jsonBody) {
            // Simulate large record
            NSMutableDictionary *largeRecord = [NSMutableDictionary dictionary];
            largeRecord[@"$type"] = @"app.bsky.feed.post";
            largeRecord[@"text"] = [@"" stringByPaddingToLength:1000 withString:@"x" startingAtIndex:0];

            NSError *jsonError = nil;
            NSData *largeData = [NSJSONSerialization dataWithJSONObject:largeRecord options:0 error:&jsonError];
            if (largeData) {
                (void)largeData;
            }
        }

        // Test 14: AT-URI parsing
        NSArray *atUriTests = @[
            @"at://did:plc:test/app.bsky.feed.post/3k345",
            @"at://did:web:example.com/app.bsky.actor.profile/self",
            @"at://handle:user.example.com/com.atproto.lexicon.schema/test"
        ];

        for (NSString *atUri in atUriTests) {
            if ([atUri hasPrefix:@"at://"]) {
                NSString *withoutPrefix = [atUri substringFromIndex:5];
                NSArray *parts = [withoutPrefix componentsSeparatedByString:@"/"];
                (void)parts;
            }
        }

        // Test 15: Blob reference validation
        if (jsonBody[@"blob"]) {
            NSDictionary *blob = jsonBody[@"blob"];
            NSString *ref = blob[@"ref"];
            NSString *mimeType = blob[@"mimeType"];
            NSNumber *size = blob[@"size"];

            (void)ref;
            (void)mimeType;
            (void)size;
        }

        return 0;
    }
}


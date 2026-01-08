#import <XCTest/XCTest.h>
#import "Core/DID.h"

@interface DIDResolver (Testing)

- (NSError *)validateDID:(NSString *)did;
- (NSDictionary *)cachedEntryForDID:(NSString *)did status:(DIDCacheStatus *)outStatus;
- (void)cacheDocument:(DIDDocument *)document forDID:(NSString *)did;
- (NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error;

@end

@interface DIDResolverTests : XCTestCase

@property (nonatomic, strong) DIDResolver *resolver;

@end

@implementation DIDResolverTests

- (void)setUp {
    [super setUp];
    self.resolver = [[DIDResolver alloc] init];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testDIDResolverInitialization {
    XCTAssertNotNil(self.resolver, @"Resolver should be initialized");
    XCTAssertNotNil([self.resolver valueForKey:@"_session"], @"Session should be initialized");
    XCTAssertNotNil([self.resolver valueForKey:@"_cache"], @"Cache should be initialized");
    XCTAssertEqual([[self.resolver valueForKey:@"_staleTTL"] doubleValue], 3600.0, @"Stale TTL should be 3600");
    XCTAssertEqual([[self.resolver valueForKey:@"_maxTTL"] doubleValue], 86400.0, @"Max TTL should be 86400");
}

- (void)testDIDValidationEmptyString {
    NSError *error = [self.resolver validateDID:@""];

    XCTAssertNotNil(error, @"Empty DID should return error");
    XCTAssertEqual(error.code, DIDErrorInvalidIdentifier, @"Error code should be DIDErrorInvalidIdentifier");
}

- (void)testDIDValidationNullString {
    NSError *error = [self.resolver validateDID:nil];

    XCTAssertNotNil(error, @"Nil DID should return error");
    XCTAssertEqual(error.code, DIDErrorInvalidIdentifier, @"Error code should be DIDErrorInvalidIdentifier");
}

- (void)testDIDValidationMissingPrefix {
    NSError *error = [self.resolver validateDID:@"example.com"];

    XCTAssertNotNil(error, @"DID without prefix should return error");
    XCTAssertEqual(error.code, DIDErrorInvalidIdentifier, @"Error code should be DIDErrorInvalidIdentifier");
}

- (void)testDIDValidationValidWebDID {
    NSError *error = [self.resolver validateDID:@"did:web:example.com"];

    XCTAssertNil(error, @"Valid web DID should not return error");
}

- (void)testDIDValidationValidPLCDID {
    NSError *error = [self.resolver validateDID:@"did:plc:7HjwGtP5cLyq3vD5nDzDg"];

    XCTAssertNil(error, @"Valid PLC DID should not return error");
}

- (void)testCachingFreshDocument {
    NSDictionary *json = @{@"id": @"did:web:cached.example.com"};
    NSError *error = nil;
    DIDDocument *doc = [DIDDocument documentWithJSON:json error:&error];
    XCTAssertNotNil(doc, @"Document should be created");

    [self.resolver cacheDocument:doc forDID:@"did:web:cached.example.com"];

    DIDCacheStatus status;
    NSDictionary *entry = [self.resolver cachedEntryForDID:@"did:web:cached.example.com" status:&status];

    XCTAssertNotNil(entry, @"Cache entry should exist");
    XCTAssertEqual(status, DIDCacheStatusFresh, @"Status should be fresh");
    XCTAssertEqualObjects(entry[@"document"], doc, @"Document in cache should match");
}

- (void)testCachingStaleDocument {
    NSDictionary *json = @{@"id": @"did:web:cached.example.com"};
    NSError *error = nil;
    DIDDocument *doc = [DIDDocument documentWithJSON:json error:&error];
    XCTAssertNotNil(doc, @"Document should be created");

    [self.resolver cacheDocument:doc forDID:@"did:web:cached.example.com"];

    NSDate *oldDate = [NSDate dateWithTimeIntervalSinceNow:-7200];
    NSDictionary *oldEntry = @{@"document": doc, @"timestamp": oldDate};
    [[self.resolver valueForKey:@"_cache"] setObject:oldEntry forKey:@"did:web:cached.example.com"];

    DIDCacheStatus status;
    NSDictionary *entry = [self.resolver cachedEntryForDID:@"did:web:cached.example.com" status:&status];

    XCTAssertNotNil(entry, @"Cache entry should exist");
    XCTAssertEqual(status, DIDCacheStatusStale, @"Status should be stale");
}

- (void)testCachingExpiredDocument {
    NSDictionary *json = @{@"id": @"did:web:cached.example.com"};
    NSError *error = nil;
    DIDDocument *doc = [DIDDocument documentWithJSON:json error:&error];
    XCTAssertNotNil(doc, @"Document should be created");

    [self.resolver cacheDocument:doc forDID:@"did:web:cached.example.com"];

    NSDate *veryOldDate = [NSDate dateWithTimeIntervalSinceNow:-172800];
    NSDictionary *veryOldEntry = @{@"document": doc, @"timestamp": veryOldDate};
    [[self.resolver valueForKey:@"_cache"] setObject:veryOldEntry forKey:@"did:web:cached.example.com"];

    DIDCacheStatus status;
    NSDictionary *entry = [self.resolver cachedEntryForDID:@"did:web:cached.example.com" status:&status];

    XCTAssertNil(entry, @"Expired entry should not exist");
    XCTAssertEqual(status, DIDCacheStatusExpired, @"Status should be expired");
}

- (void)testCachingNonExistentDID {
    DIDCacheStatus status;
    NSDictionary *entry = [self.resolver cachedEntryForDID:@"did:web:nonexistent.example.com" status:&status];

    XCTAssertNil(entry, @"Non-existent DID should have no entry");
    XCTAssertEqual(status, DIDCacheStatusExpired, @"Status should be expired");
}

- (void)testUnsupportedDIDMethod {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Unsupported method test"];

    [self.resolver resolveDID:@"did:key:zQ3shP2mL9Xqgk2T5Lf" forceRefresh:NO completion:^(DIDDocument *document, NSError *resolveError) {
        XCTAssertNil(document, @"Unsupported method should return nil document");
        XCTAssertNotNil(resolveError, @"Error should be set for unsupported method");
        XCTAssertEqual(resolveError.code, DIDErrorInvalidIdentifier, @"Error code should be DIDErrorInvalidIdentifier");
        XCTAssertTrue([resolveError.localizedDescription containsString:@"Unsupported DID method"], @"Error should mention unsupported method");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testSyncResolutionInvalidDID {
    NSError *error = nil;
    DIDDocument *syncDoc = [self.resolver resolveDIDSync:@"" error:&error];

    XCTAssertNil(syncDoc, @"Invalid DID should return nil document");
    XCTAssertNotNil(error, @"Error should be set for invalid DID");
    XCTAssertEqual(error.code, DIDErrorInvalidIdentifier, @"Error code should be DIDErrorInvalidIdentifier");
}

- (void)testAtprotoDataExtractionComplete {
    NSDictionary *completeJson = @{
        @"id": @"did:plc:test123",
        @"alsoKnownAs": @[@"at://test.example.com"],
        @"service": @[@{
            @"id": @"#atproto_pds",
            @"type": @"AtprotoPersonalDataServer",
            @"serviceEndpoint": @"https://pds.example.com"
        }],
        @"verificationMethod": @[@{
            @"id": @"#key-1",
            @"type": @"EcdsaSecp256k1VerificationKey2019",
            @"publicKeyMultibase": @"z7r8ciZ2VJyC7gZF5yKjQ5vz7r8ciZ2VJyC7gZF5yKj"
        }]
    };

    NSError *error = nil;
    DIDDocument *completeDoc = [DIDDocument documentWithJSON:completeJson error:&error];
    XCTAssertNotNil(completeDoc, @"Document should be created");
    [self.resolver cacheDocument:completeDoc forDID:@"did:plc:test123"];

    NSDictionary *atprotoData = [self.resolver resolveAtprotoDataForDID:@"did:plc:test123" error:&error];

    XCTAssertNotNil(atprotoData, @"Atproto data should be extracted");
    XCTAssertEqualObjects(atprotoData[@"did"], @"did:plc:test123", @"DID should match");
    XCTAssertEqualObjects(atprotoData[@"handle"], @"at://test.example.com", @"Handle should match");
    XCTAssertEqualObjects(atprotoData[@"pds"], @"https://pds.example.com", @"PDS should match");
    XCTAssertEqualObjects(atprotoData[@"signingKey"], @"z7r8ciZ2VJyC7gZF5yKjQ5vz7r8ciZ2VJyC7gZF5yKj", @"Signing key should match");
}

- (void)testAtprotoDataExtractionMinimal {
    NSDictionary *minimalJson = @{@"id": @"did:web:minimal.example.com"};
    NSError *error = nil;
    DIDDocument *minimalDoc = [DIDDocument documentWithJSON:minimalJson error:&error];
    XCTAssertNotNil(minimalDoc, @"Document should be created");
    [self.resolver cacheDocument:minimalDoc forDID:@"did:web:minimal.example.com"];

    NSDictionary *minimalAtprotoData = [self.resolver resolveAtprotoDataForDID:@"did:web:minimal.example.com" error:&error];

    XCTAssertNotNil(minimalAtprotoData, @"Atproto data should be extracted");
    XCTAssertEqualObjects(minimalAtprotoData[@"did"], @"did:web:minimal.example.com", @"DID should match");
    XCTAssertNil(minimalAtprotoData[@"handle"], @"Handle should be nil for minimal document");
    XCTAssertNil(minimalAtprotoData[@"pds"], @"PDS should be nil for minimal document");
    XCTAssertNil(minimalAtprotoData[@"signingKey"], @"Signing key should be nil for minimal document");
}

- (void)testDIDDocumentCreationValidJSON {
    NSDictionary *docJson = @{
        @"id": @"did:web:test.example.com",
        @"alsoKnownAs": @[@"at://test.example.com"],
        @"service": @{@"endpoint": @"https://test.example.com"}
    };
    NSError *error = nil;
    DIDDocument *testDoc = [DIDDocument documentWithJSON:docJson error:&error];

    XCTAssertNotNil(testDoc, @"Valid document should be created");
    XCTAssertEqualObjects(testDoc.id, @"did:web:test.example.com", @"DID should match");
}

- (void)testDIDDocumentCreationInvalidJSONMissingID {
    NSDictionary *invalidDocJson = @{@"alsoKnownAs": @[@"at://test.example.com"]};
    NSError *error = nil;
    DIDDocument *invalidTestDoc = [DIDDocument documentWithJSON:invalidDocJson error:&error];

    XCTAssertNil(invalidTestDoc, @"Invalid document should be nil");
    XCTAssertNotNil(error, @"Error should be set");
    XCTAssertEqual(error.code, DIDErrorInvalidDocument, @"Error code should be DIDErrorInvalidDocument");
}

- (void)testDIDDocumentCreationInvalidJSONNotDictionary {
    NSError *error = nil;
    DIDDocument *invalidTypeDoc = [DIDDocument documentWithJSON:@"not a dict" error:&error];

    XCTAssertNil(invalidTypeDoc, @"Invalid type document should be nil");
    XCTAssertNotNil(error, @"Error should be set");
    XCTAssertEqual(error.code, DIDErrorInvalidDocument, @"Error code should be DIDErrorInvalidDocument");
}

- (void)testDIDWebURLConstructionBasicDomain {
    NSError *error = [self.resolver validateDID:@"did:web:example.com"];
    XCTAssertNil(error, @"Valid web DID should not return error");
}

- (void)testDIDWebURLConstructionWithPath {
    NSError *error = [self.resolver validateDID:@"did:web:example.com:user:profile"];
    XCTAssertNil(error, @"Valid web DID with path should not return error");
}

- (void)testCacheThreadSafety {
    dispatch_queue_t queue = dispatch_queue_create("test.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    __block BOOL threadSafetyPassed = YES;

    for (int i = 0; i < 10; i++) {
        dispatch_group_async(group, queue, ^{
            @autoreleasepool {
                NSString *threadDID = [NSString stringWithFormat:@"did:web:thread%d.example.com", i];
                NSDictionary *threadJson = @{@"id": threadDID};
                NSError *error = nil;
                DIDDocument *threadDoc = [DIDDocument documentWithJSON:threadJson error:&error];
                if (threadDoc) {
                    [self.resolver cacheDocument:threadDoc forDID:threadDID];

                    DIDCacheStatus threadStatus;
                    NSDictionary *threadEntry = [self.resolver cachedEntryForDID:threadDID status:&threadStatus];
                    if (!threadEntry || threadStatus != DIDCacheStatusFresh) {
                        threadSafetyPassed = NO;
                    }
                } else {
                    threadSafetyPassed = NO;
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    XCTAssertTrue(threadSafetyPassed, @"Cache operations should be thread-safe");
}

- (void)testConcurrentResolutions {
    NSArray *concurrentDIDs = @[@"did:web:conc1.example.com", @"did:web:conc2.example.com", @"did:web:conc3.example.com"];

    for (NSString *concurrentDID in concurrentDIDs) {
        NSDictionary *concurrentJson = @{@"id": concurrentDID};
        NSError *error = nil;
        DIDDocument *concurrentDoc = [DIDDocument documentWithJSON:concurrentJson error:&error];
        if (concurrentDoc) {
            [self.resolver cacheDocument:concurrentDoc forDID:concurrentDID];
        }
    }

    dispatch_group_t concurrentGroup = dispatch_group_create();
    __block NSUInteger concurrentCompleted = 0;
    __block BOOL concurrentPassed = YES;

    for (NSString *concurrentDID in concurrentDIDs) {
        dispatch_group_enter(concurrentGroup);
        [self.resolver resolveDID:concurrentDID forceRefresh:NO completion:^(DIDDocument *document, NSError *resolveError) {
            if (!document || resolveError) {
                concurrentPassed = NO;
            }
            concurrentCompleted++;
            dispatch_group_leave(concurrentGroup);
        }];
    }

    dispatch_group_wait(concurrentGroup, DISPATCH_TIME_FOREVER);

    XCTAssertTrue(concurrentPassed, @"All concurrent resolutions should succeed");
    XCTAssertEqual(concurrentCompleted, concurrentDIDs.count, @"All resolutions should complete");
}

- (void)testMemoryManagement {
    @autoreleasepool {
        DIDResolver *tempResolver = [[DIDResolver alloc] init];
        NSDictionary *tempJson = @{@"id": @"did:web:temp.example.com"};
        NSError *error = nil;
        DIDDocument *tempDoc = [DIDDocument documentWithJSON:tempJson error:&error];
        XCTAssertNotNil(tempDoc, @"Temp document should be created");
        [tempResolver cacheDocument:tempDoc forDID:@"did:web:temp.example.com"];

        DIDCacheStatus tempStatus;
        NSDictionary *tempEntry = [tempResolver cachedEntryForDID:@"did:web:temp.example.com" status:&tempStatus];
        XCTAssertNotNil(tempEntry, @"Temp entry should exist");
        XCTAssertEqual(tempStatus, DIDCacheStatusFresh, @"Temp status should be fresh");
    }
}

- (void)testErrorDomainConsistency {
    NSError *error = [self.resolver validateDID:@""];
    XCTAssertNotNil(error, @"Error should be returned");
    XCTAssertEqualObjects(error.domain, DIDErrorDomain, @"Error domain should be DIDErrorDomain");
}

- (void)testLargeDIDHandling {
    NSString *largeDID = [@"" stringByPaddingToLength:2000 withString:@"did:web:very-long-domain-name-that-might-cause-issues.example.com" startingAtIndex:0];
    NSError *error = [self.resolver validateDID:largeDID];

    XCTAssertTrue(!error || (error && error.code == DIDErrorInvalidIdentifier), @"Large DID should either pass or fail gracefully");
}

- (void)testCacheSizeManagement {
    NSUInteger initialCacheCount = [[self.resolver valueForKey:@"_cache"] count];

    for (int i = 0; i < 100; i++) {
        NSString *cacheDID = [NSString stringWithFormat:@"did:web:cachetest%d.example.com", i];
        NSDictionary *cacheJson = @{@"id": cacheDID};
        NSError *error = nil;
        DIDDocument *cacheDoc = [DIDDocument documentWithJSON:cacheJson error:&error];
        if (cacheDoc) {
            [self.resolver cacheDocument:cacheDoc forDID:cacheDID];
        }
    }

    NSUInteger finalCacheCount = [[self.resolver valueForKey:@"_cache"] count];
    XCTAssertGreaterThanOrEqual(finalCacheCount, initialCacheCount + 100, @"Cache should grow with new entries");
}

@end

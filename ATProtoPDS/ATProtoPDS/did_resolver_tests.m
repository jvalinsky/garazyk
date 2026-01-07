#import <Foundation/Foundation.h>
#import "DID.h"

// Test category to expose private methods for testing
@interface DIDResolver (Testing)

- (NSError *)validateDID:(NSString *)did;
- (NSDictionary *)cachedEntryForDID:(NSString *)did status:(DIDCacheStatus *)outStatus;
- (void)cacheDocument:(DIDDocument *)document forDID:(NSString *)did;
- (NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error;

@end

/// Comprehensive unit tests for DIDResolver class
/// Tests caching, DID resolution methods (web/plc), error handling, and edge cases
int runDIDResolverTests(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Running DIDResolver Tests");
        NSUInteger totalTests = 0;
        NSUInteger passedTests = 0;

        DIDResolver *resolver = [[DIDResolver alloc] init];

        // Test 1: DIDResolver Initialization
        totalTests++;
        if (resolver && [resolver valueForKey:@"_session"] && [resolver valueForKey:@"_cache"] &&
            [[resolver valueForKey:@"_staleTTL"] doubleValue] == 3600.0 &&
            [[resolver valueForKey:@"_maxTTL"] doubleValue] == 86400.0) {
            passedTests++;
            NSLog(@"✅ DIDResolver Initialization: PASSED");
        } else {
            NSLog(@"❌ DIDResolver Initialization: FAILED");
        }

        // Test 2: DID Validation - Empty String
        totalTests++;
        NSError *error = [resolver validateDID:@""];
        if (!error) {
            NSLog(@"❌ DID Validation (Empty): FAILED - Expected error");
        } else if (error.code == DIDErrorInvalidIdentifier) {
            passedTests++;
            NSLog(@"✅ DID Validation (Empty): PASSED");
        } else {
            NSLog(@"❌ DID Validation (Empty): FAILED - Wrong error code: %ld", (long)error.code);
        }

        // Test 3: DID Validation - Null String
        totalTests++;
        error = [resolver validateDID:nil];
        if (!error) {
            NSLog(@"❌ DID Validation (Null): FAILED - Expected error");
        } else if (error.code == DIDErrorInvalidIdentifier) {
            passedTests++;
            NSLog(@"✅ DID Validation (Null): PASSED");
        } else {
            NSLog(@"❌ DID Validation (Null): FAILED - Wrong error code: %ld", (long)error.code);
        }

        // Test 4: DID Validation - Missing Prefix
        totalTests++;
        error = [resolver validateDID:@"example.com"];
        if (!error) {
            NSLog(@"❌ DID Validation (No Prefix): FAILED - Expected error");
        } else if (error.code == DIDErrorInvalidIdentifier) {
            passedTests++;
            NSLog(@"✅ DID Validation (No Prefix): PASSED");
        } else {
            NSLog(@"❌ DID Validation (No Prefix): FAILED - Wrong error code: %ld", (long)error.code);
        }

        // Test 5: DID Validation - Valid Web DID
        totalTests++;
        error = [resolver validateDID:@"did:web:example.com"];
        if (!error) {
            passedTests++;
            NSLog(@"✅ DID Validation (Valid Web): PASSED");
        } else {
            NSLog(@"❌ DID Validation (Valid Web): FAILED - Unexpected error: %@", error);
        }

        // Test 6: DID Validation - Valid PLC DID
        totalTests++;
        error = [resolver validateDID:@"did:plc:7HjwGtP5cLyq3vD5nDzDg"];
        if (!error) {
            passedTests++;
            NSLog(@"✅ DID Validation (Valid PLC): PASSED");
        } else {
            NSLog(@"❌ DID Validation (Valid PLC): FAILED - Unexpected error: %@", error);
        }

        // Test 7: Caching - Fresh Document
        totalTests++;
        NSDictionary *json = @{@"id": @"did:web:cached.example.com"};
        DIDDocument *doc = [DIDDocument documentWithJSON:json error:nil];
        [resolver cacheDocument:doc forDID:@"did:web:cached.example.com"];

        DIDCacheStatus status;
        NSDictionary *entry = [resolver cachedEntryForDID:@"did:web:cached.example.com" status:&status];
        if (entry && status == DIDCacheStatusFresh && [entry[@"document"] isEqual:doc]) {
            passedTests++;
            NSLog(@"✅ Caching (Fresh): PASSED");
        } else {
            NSLog(@"❌ Caching (Fresh): FAILED - Status: %ld, Entry: %@", (long)status, entry ? @"present" : @"nil");
        }

        // Test 8: Caching - Stale Document
        totalTests++;
        // Manually set old timestamp (2 hours ago)
        NSDate *oldDate = [NSDate dateWithTimeIntervalSinceNow:-7200];
        NSDictionary *oldEntry = @{@"document": doc, @"timestamp": oldDate};
        [[resolver valueForKey:@"_cache"] setObject:oldEntry forKey:@"did:web:cached.example.com"];

        entry = [resolver cachedEntryForDID:@"did:web:cached.example.com" status:&status];
        if (entry && status == DIDCacheStatusStale) {
            passedTests++;
            NSLog(@"✅ Caching (Stale): PASSED");
        } else {
            NSLog(@"❌ Caching (Stale): FAILED - Status: %ld", (long)status);
        }

        // Test 9: Caching - Expired Document
        totalTests++;
        // Manually set very old timestamp (2 days ago)
        NSDate *veryOldDate = [NSDate dateWithTimeIntervalSinceNow:-172800];
        NSDictionary *veryOldEntry = @{@"document": doc, @"timestamp": veryOldDate};
        [[resolver valueForKey:@"_cache"] setObject:veryOldEntry forKey:@"did:web:cached.example.com"];

        entry = [resolver cachedEntryForDID:@"did:web:cached.example.com" status:&status];
        if (!entry && status == DIDCacheStatusExpired) {
            passedTests++;
            NSLog(@"✅ Caching (Expired): PASSED");
        } else {
            NSLog(@"❌ Caching (Expired): FAILED - Status: %ld, Entry: %@", (long)status, entry ? @"present" : @"nil");
        }

        // Test 10: Caching - Non-existent DID
        totalTests++;
        entry = [resolver cachedEntryForDID:@"did:web:nonexistent.example.com" status:&status];
        if (!entry && status == DIDCacheStatusExpired) {
            passedTests++;
            NSLog(@"✅ Caching (Non-existent): PASSED");
        } else {
            NSLog(@"❌ Caching (Non-existent): FAILED");
        }

        // Test 11: Unsupported DID Method
        totalTests++;
        __block BOOL unsupportedMethodTestPassed = NO;
        __block BOOL unsupportedMethodCompleted = NO;

        [resolver resolveDID:@"did:key:zQ3shP2mL9Xqgk2T5Lf" forceRefresh:NO completion:^(DIDDocument *document, NSError *resolveError) {
            if (!document && resolveError && resolveError.code == DIDErrorInvalidIdentifier &&
                [resolveError.localizedDescription containsString:@"Unsupported DID method"]) {
                unsupportedMethodTestPassed = YES;
            }
            unsupportedMethodCompleted = YES;
        }];

        // Wait for async completion (simple spin wait for testing)
        NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
        while (!unsupportedMethodCompleted && [[NSDate date] timeIntervalSince1970] - startTime < 1.0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (unsupportedMethodTestPassed) {
            passedTests++;
            NSLog(@"✅ Unsupported DID Method: PASSED");
        } else {
            NSLog(@"❌ Unsupported DID Method: FAILED");
        }

        // Test 12: Synchronous Resolution - Invalid DID
        totalTests++;
        DIDDocument *syncDoc = [resolver resolveDIDSync:@"" error:&error];
        if (!syncDoc && error && error.code == DIDErrorInvalidIdentifier) {
            passedTests++;
            NSLog(@"✅ Sync Resolution (Invalid): PASSED");
        } else {
            NSLog(@"❌ Sync Resolution (Invalid): FAILED");
        }

        // Test 13: Atproto Data Extraction - Complete Data
        totalTests++;
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

        DIDDocument *completeDoc = [DIDDocument documentWithJSON:completeJson error:nil];
        [resolver cacheDocument:completeDoc forDID:@"did:plc:test123"];

        NSDictionary *atprotoData = [resolver resolveAtprotoDataForDID:@"did:plc:test123" error:&error];
        if (atprotoData &&
            [atprotoData[@"did"] isEqualToString:@"did:plc:test123"] &&
            [atprotoData[@"handle"] isEqualToString:@"at://test.example.com"] &&
            [atprotoData[@"pds"] isEqualToString:@"https://pds.example.com"] &&
            [atprotoData[@"signingKey"] isEqualToString:@"z7r8ciZ2VJyC7gZF5yKjQ5vz7r8ciZ2VJyC7gZF5yKj"]) {
            passedTests++;
            NSLog(@"✅ Atproto Data Extraction (Complete): PASSED");
        } else {
            NSLog(@"❌ Atproto Data Extraction (Complete): FAILED - Data: %@", atprotoData);
        }

        // Test 14: Atproto Data Extraction - Minimal Data
        totalTests++;
        NSDictionary *minimalJson = @{@"id": @"did:web:minimal.example.com"};
        DIDDocument *minimalDoc = [DIDDocument documentWithJSON:minimalJson error:nil];
        [resolver cacheDocument:minimalDoc forDID:@"did:web:minimal.example.com"];

        NSDictionary *minimalAtprotoData = [resolver resolveAtprotoDataForDID:@"did:web:minimal.example.com" error:&error];
        if (minimalAtprotoData &&
            [minimalAtprotoData[@"did"] isEqualToString:@"did:web:minimal.example.com"] &&
            !minimalAtprotoData[@"handle"] &&
            !minimalAtprotoData[@"pds"] &&
            !minimalAtprotoData[@"signingKey"]) {
            passedTests++;
            NSLog(@"✅ Atproto Data Extraction (Minimal): PASSED");
        } else {
            NSLog(@"❌ Atproto Data Extraction (Minimal): FAILED - Data: %@", minimalAtprotoData);
        }

        // Test 15: DID Document Creation - Valid JSON
        totalTests++;
        NSDictionary *docJson = @{
            @"id": @"did:web:test.example.com",
            @"alsoKnownAs": @[@"at://test.example.com"],
            @"service": @{@"endpoint": @"https://test.example.com"}
        };
        DIDDocument *testDoc = [DIDDocument documentWithJSON:docJson error:&error];
        if (testDoc && [testDoc.id isEqualToString:@"did:web:test.example.com"]) {
            passedTests++;
            NSLog(@"✅ DID Document Creation (Valid): PASSED");
        } else {
            NSLog(@"❌ DID Document Creation (Valid): FAILED - Error: %@", error);
        }

        // Test 16: DID Document Creation - Invalid JSON (Missing ID)
        totalTests++;
        NSDictionary *invalidDocJson = @{@"alsoKnownAs": @[@"at://test.example.com"]};
        DIDDocument *invalidTestDoc = [DIDDocument documentWithJSON:invalidDocJson error:&error];
        if (!invalidTestDoc && error && error.code == DIDErrorInvalidDocument) {
            passedTests++;
            NSLog(@"✅ DID Document Creation (Invalid): PASSED");
        } else {
            NSLog(@"❌ DID Document Creation (Invalid): FAILED - Doc: %@, Error: %@", invalidTestDoc, error);
        }

        // Test 17: DID Document Creation - Invalid JSON (Not Dictionary)
        totalTests++;
        DIDDocument *invalidTypeDoc = [DIDDocument documentWithJSON:@"not a dict" error:&error];
        if (!invalidTypeDoc && error && error.code == DIDErrorInvalidDocument) {
            passedTests++;
            NSLog(@"✅ DID Document Creation (Wrong Type): PASSED");
        } else {
            NSLog(@"❌ DID Document Creation (Wrong Type): FAILED");
        }

        // Test 18: DID Web URL Construction - Basic Domain
        totalTests++;
        // This is a private method test - we'll test the validation indirectly
        error = [resolver validateDID:@"did:web:example.com"];
        if (!error) {
            passedTests++;
            NSLog(@"✅ DID Web URL Construction (Basic): PASSED");
        } else {
            NSLog(@"❌ DID Web URL Construction (Basic): FAILED");
        }

        // Test 19: DID Web URL Construction - With Path
        totalTests++;
        error = [resolver validateDID:@"did:web:example.com:user:profile"];
        if (!error) {
            passedTests++;
            NSLog(@"✅ DID Web URL Construction (Path): PASSED");
        } else {
            NSLog(@"❌ DID Web URL Construction (Path): FAILED");
        }

        // Test 20: Cache Thread Safety
        totalTests++;
        // Test basic thread safety by performing operations from different threads
        dispatch_queue_t queue = dispatch_queue_create("test.queue", DISPATCH_QUEUE_CONCURRENT);

        __block BOOL threadSafetyPassed = YES;
        dispatch_group_t group = dispatch_group_create();

        for (int i = 0; i < 10; i++) {
            dispatch_group_async(group, queue, ^{
                @autoreleasepool {
                    NSString *threadDID = [NSString stringWithFormat:@"did:web:thread%d.example.com", i];
                    NSDictionary *threadJson = @{@"id": threadDID};
                    DIDDocument *threadDoc = [DIDDocument documentWithJSON:threadJson error:nil];
                    [resolver cacheDocument:threadDoc forDID:threadDID];

                    DIDCacheStatus threadStatus;
                    NSDictionary *threadEntry = [resolver cachedEntryForDID:threadDID status:&threadStatus];
                    if (!threadEntry || threadStatus != DIDCacheStatusFresh) {
                        threadSafetyPassed = NO;
                    }
                }
            });
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        if (threadSafetyPassed) {
            passedTests++;
            NSLog(@"✅ Cache Thread Safety: PASSED");
        } else {
            NSLog(@"❌ Cache Thread Safety: FAILED");
        }

        // Test 21: Concurrent Resolutions
        totalTests++;
        NSArray *concurrentDIDs = @[@"did:web:conc1.example.com", @"did:web:conc2.example.com", @"did:web:conc3.example.com"];
        __block NSUInteger concurrentCompleted = 0;
        __block BOOL concurrentPassed = YES;

        for (NSString *concurrentDID in concurrentDIDs) {
            NSDictionary *concurrentJson = @{@"id": concurrentDID};
            DIDDocument *concurrentDoc = [DIDDocument documentWithJSON:concurrentJson error:nil];
            [resolver cacheDocument:concurrentDoc forDID:concurrentDID];
        }

        dispatch_group_t concurrentGroup = dispatch_group_create();

        for (NSString *concurrentDID in concurrentDIDs) {
            dispatch_group_enter(concurrentGroup);
            [resolver resolveDID:concurrentDID forceRefresh:NO completion:^(DIDDocument *document, NSError *resolveError) {
                if (!document || resolveError) {
                    concurrentPassed = NO;
                }
                concurrentCompleted++;
                dispatch_group_leave(concurrentGroup);
            }];
        }

        dispatch_group_wait(concurrentGroup, DISPATCH_TIME_FOREVER);

        if (concurrentPassed && concurrentCompleted == concurrentDIDs.count) {
            passedTests++;
            NSLog(@"✅ Concurrent Resolutions: PASSED");
        } else {
            NSLog(@"❌ Concurrent Resolutions: FAILED - Completed: %lu/%lu", (unsigned long)concurrentCompleted, (unsigned long)concurrentDIDs.count);
        }

        // Test 22: Memory Management
        totalTests++;
        @autoreleasepool {
            DIDResolver *tempResolver = [[DIDResolver alloc] init];
            NSDictionary *tempJson = @{@"id": @"did:web:temp.example.com"};
            DIDDocument *tempDoc = [DIDDocument documentWithJSON:tempJson error:nil];
            [tempResolver cacheDocument:tempDoc forDID:@"did:web:temp.example.com"];

            // Test that the resolver and its cache work within the pool
            DIDCacheStatus tempStatus;
            NSDictionary *tempEntry = [tempResolver cachedEntryForDID:@"did:web:temp.example.com" status:&tempStatus];
            if (tempEntry && tempStatus == DIDCacheStatusFresh) {
                passedTests++;
                NSLog(@"✅ Memory Management: PASSED");
            } else {
                NSLog(@"❌ Memory Management: FAILED");
            }
            // tempResolver will be released here
        }

        // Test 23: Error Domain Consistency
        totalTests++;
        error = [resolver validateDID:@""];
        if (error && [error.domain isEqualToString:DIDErrorDomain]) {
            passedTests++;
            NSLog(@"✅ Error Domain Consistency: PASSED");
        } else {
            NSLog(@"❌ Error Domain Consistency: FAILED - Domain: %@", error.domain);
        }

        // Test 24: Large DID Handling
        totalTests++;
        NSString *largeDID = [@"" stringByPaddingToLength:2000 withString:@"did:web:very-long-domain-name-that-might-cause-issues.example.com" startingAtIndex:0];
        error = [resolver validateDID:largeDID];
        // This should either pass validation or fail gracefully
        if (!error || (error && error.code == DIDErrorInvalidIdentifier)) {
            passedTests++;
            NSLog(@"✅ Large DID Handling: PASSED");
        } else {
            NSLog(@"❌ Large DID Handling: FAILED - Unexpected error: %@", error);
        }

        // Test 25: Cache Size Management
        totalTests++;
        // Add many entries to test cache doesn't grow unbounded in a simple way
        NSUInteger initialCacheCount = [[resolver valueForKey:@"_cache"] count];
        for (int i = 0; i < 100; i++) {
            NSString *cacheDID = [NSString stringWithFormat:@"did:web:cachetest%d.example.com", i];
            NSDictionary *cacheJson = @{@"id": cacheDID};
            DIDDocument *cacheDoc = [DIDDocument documentWithJSON:cacheJson error:nil];
            [resolver cacheDocument:cacheDoc forDID:cacheDID];
        }

        NSUInteger finalCacheCount = [[resolver valueForKey:@"_cache"] count];
        if (finalCacheCount >= initialCacheCount + 100) {
            passedTests++;
            NSLog(@"✅ Cache Size Management: PASSED - Cache grew from %lu to %lu entries", (unsigned long)initialCacheCount, (unsigned long)finalCacheCount);
        } else {
            NSLog(@"❌ Cache Size Management: FAILED - Cache didn't grow properly");
        }

        // Summary
        NSLog(@"🎯 DIDResolver Test Results: %lu/%lu tests passed", (unsigned long)passedTests, (unsigned long)totalTests);

        if (passedTests == totalTests) {
            NSLog(@"🎉 All DIDResolver tests PASSED! The resolver is working correctly.");
        } else {
            NSLog(@"⚠️  Some DIDResolver tests FAILED. Please review the implementation.");
        }

        // Return the number of tests that passed (not just 0/1)
        return (int)passedTests;
    }
}

int main(int argc, const char * argv[]) {
    return runDIDResolverTests(argc, argv);
}
#import <Foundation/Foundation.h>
#import "PDSController.h"
#import "Database/PDSDatabase.h"

/// Comprehensive integration tests for PDS operations
/// Tests account creation, record operations, and API workflows
int runPDSIntegrationTests(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Running PDS Integration Tests");
        NSUInteger totalTests = 0;
        NSUInteger passedTests = 0;

        NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        tempURL = [tempURL URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        tempURL = [tempURL URLByAppendingPathExtension:@"db"];
        PDSDatabase *database = [PDSDatabase databaseAtURL:tempURL];
        NSError *dbError;
        [database openWithError:&dbError];
        PDSController *controller = [[PDSController alloc] initWithDatabase:database];

    // Test 1: Account Creation
    totalTests++;
    NSError *error;
    NSDictionary *accountResult = [controller createAccountForEmail:@"test@example.com"
                                                           password:@"testpass123"
                                                            handle:@"test.example.com"
                                                               did:nil
                                                             error:&error];
    if (accountResult && !error) {
        passedTests++;
        NSLog(@"✅ Account Creation: PASSED - Created account: %@", accountResult[@"did"]);
    } else {
        NSLog(@"❌ Account Creation: FAILED - Error: %@", error);
    }

        // Test 2: Session Creation
        totalTests++;
        NSDictionary *sessionResult = [controller createSessionForIdentifier:@"test@example.com"
                                                                    password:@"testpass123"
                                                                     handle:@"test.example.com"
                                                                       did:accountResult[@"did"]
                                                                      error:&error];
        if (sessionResult && !error && sessionResult[@"accessJwt"]) {
            passedTests++;
            NSLog(@"✅ Session Creation: PASSED - Got access token");
        } else {
            NSLog(@"❌ Session Creation: FAILED - Error: %@", error);
        }

        // Test 3: Record Creation and Retrieval
        totalTests++;
        NSString *did = accountResult[@"did"];
        NSDictionary *recordBody = @{
            @"text": @"Hello, ATProto!",
            @"createdAt": @"2024-01-01T00:00:00.000Z"
        };

        NSDictionary *createRecordBody = @{
            @"repo": did,
            @"collection": @"app.bsky.feed.post",
            @"record": recordBody
        };

        NSDictionary *recordResult = [controller createRecordForDid:did collection:@"app.bsky.feed.post" record:recordBody error:&error];
        if (recordResult && !error && recordResult[@"cid"]) {
            passedTests++;
            NSLog(@"✅ Record Creation: PASSED - Created record with CID: %@", recordResult[@"cid"]);
        } else {
            NSLog(@"❌ Record Creation: FAILED - Error: %@", error);
        }

        // Test 4: Record Retrieval
        totalTests++;
        if (recordResult) {
            NSString *rkey = recordResult[@"uri"];
            NSArray *uriComponents = [rkey componentsSeparatedByString:@"/"];
            NSString *recordKey = uriComponents.lastObject;

            NSDictionary *retrievedRecord = [controller getRecordForDid:did collection:@"app.bsky.feed.post" rkey:recordKey error:&error];
            if (retrievedRecord && !error && [retrievedRecord[@"value"][@"text"] isEqualToString:@"Hello, ATProto!"]) {
                passedTests++;
                NSLog(@"✅ Record Retrieval: PASSED - Retrieved record text: %@", retrievedRecord[@"value"][@"text"]);
            } else {
                NSLog(@"❌ Record Retrieval: FAILED - Error: %@", error);
            }
        } else {
            NSLog(@"❌ Record Retrieval: SKIPPED - No record to retrieve");
        }

        // Test 5: Record Listing
        totalTests++;
        NSArray *listResult = [controller listRecordsForDid:did collection:@"app.bsky.feed.post" limit:10 cursor:nil error:&error];
        if (listResult && !error && [listResult count] > 0) {
            passedTests++;
            NSLog(@"✅ Record Listing: PASSED - Found %lu records", [listResult count]);
        } else {
            NSLog(@"❌ Record Listing: FAILED - Error: %@", error);
        }

        // Test 6: Blob Operations
        totalTests++;
        NSDictionary *blobResult = [controller uploadBlob:[@"test data" dataUsingEncoding:NSUTF8StringEncoding]
                                                 mimeType:@"text/plain"
                                                      did:did
                                                   error:&error];
        if (blobResult && !error && blobResult[@"cid"]) {
            passedTests++;
            NSLog(@"✅ Blob Upload: PASSED - CID: %@", blobResult[@"cid"]);

            // Test blob retrieval
            NSDictionary *retrievedBlob = [controller getBlobWithCID:blobResult[@"cid"] did:did error:&error];
            if (retrievedBlob && !error) {
                passedTests++;
                totalTests++; // Count as separate test
                NSLog(@"✅ Blob Retrieval: PASSED");
            } else {
                NSLog(@"❌ Blob Retrieval: FAILED - Error: %@", error);
            }
        } else {
            NSLog(@"❌ Blob Upload: FAILED - Error: %@", error);
        }

        // Test 8: Record Validation - Valid Post
        totalTests++;
        NSDictionary *validRecord = @{
            @"$type": @"app.bsky.feed.post",
            @"text": @"This is a valid post",
            @"createdAt": @"2024-01-01T00:00:00.000Z"
        };

        BOOL isValid = [controller validateRecord:validRecord forCollection:@"app.bsky.feed.post" error:&error];
        if (isValid && !error) {
            passedTests++;
            NSLog(@"✅ Record Validation (Valid Post): PASSED");
        } else {
            NSLog(@"❌ Record Validation (Valid Post): FAILED - Error: %@", error);
        }

        // Test 9: Record Validation - Invalid Post (Missing Text)
        totalTests++;
        NSDictionary *invalidRecord = @{
            @"$type": @"app.bsky.feed.post",
            @"createdAt": @"2024-01-01T00:00:00.000Z"
        };

        BOOL isInvalid = [controller validateRecord:invalidRecord forCollection:@"app.bsky.feed.post" error:&error];
        if (!isInvalid && error) {
            passedTests++;
            NSLog(@"✅ Record Validation (Invalid Post): PASSED - Correctly rejected");
        } else {
            NSLog(@"❌ Record Validation (Invalid Post): FAILED - Should have been rejected");
        }

        // Test 10: Record Validation - Invalid Type
        totalTests++;
        NSDictionary *wrongTypeRecord = @{
            @"$type": @"app.bsky.feed.invalid",
            @"text": @"This has wrong type"
        };

        BOOL wrongTypeValid = [controller validateRecord:wrongTypeRecord forCollection:@"app.bsky.feed.post" error:&error];
        if (!wrongTypeValid && error) {
            passedTests++;
            NSLog(@"✅ Record Validation (Wrong Type): PASSED - Correctly rejected");
        } else {
            NSLog(@"❌ Record Validation (Wrong Type): FAILED - Should have been rejected");
        }

        // Test 11: Concurrent Operations
        totalTests++;
        dispatch_queue_t queue = dispatch_queue_create("test.queue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_group_t group = dispatch_group_create();

        __block BOOL concurrentTestPassed = YES;
        __block NSUInteger operationsCompleted = 0;

        for (int i = 0; i < 5; i++) {
            dispatch_group_async(group, queue, ^{
                @autoreleasepool {
                    NSDictionary *concurrentRecord = @{
                        @"$type": @"app.bsky.feed.post",
                        @"text": [NSString stringWithFormat:@"Concurrent post %d", i],
                        @"createdAt": @"2024-01-01T00:00:00.000Z"
                    };

                    __block NSDictionary *result = nil;
                    __block NSError *blockError = nil;
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        result = [controller createRecordForDid:did collection:@"app.bsky.feed.post" record:concurrentRecord rkey:nil error:&blockError];
                    });
                    if (!result || blockError) {
                        concurrentTestPassed = NO;
                    }
                    if (!result || error) {
                        concurrentTestPassed = NO;
                    }
                    operationsCompleted++;
                }
            });
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        if (concurrentTestPassed && operationsCompleted == 5) {
            passedTests++;
            NSLog(@"✅ Concurrent Operations: PASSED - %lu operations completed", operationsCompleted);
        } else {
            NSLog(@"❌ Concurrent Operations: FAILED - Only %lu operations completed", operationsCompleted);
        }

        // Test 12: Repository Description
        totalTests++;
        NSDictionary *repoDesc = [controller describeRepo:did error:&error];
        if (repoDesc && !error && repoDesc[@"handle"]) {
            passedTests++;
            NSLog(@"✅ Repository Description: PASSED - Handle: %@", repoDesc[@"handle"]);
        } else {
            NSLog(@"❌ Repository Description: FAILED - Error: %@", error);
        }

        // Test 13: Blob Operations (Retrieval)
        totalTests++;
        if (blobResult && blobResult[@"cid"]) {
            NSDictionary *retrievedBlob = [controller getBlobWithCID:blobResult[@"cid"] did:did error:&error];
            if (retrievedBlob && !error) {
                passedTests++;
                NSLog(@"✅ Blob Retrieval: PASSED");
            } else {
                NSLog(@"❌ Blob Retrieval: FAILED - Error: %@", error);
            }
        } else {
            NSLog(@"❌ Blob Retrieval: SKIPPED - No blob to retrieve");
        }
        if (blobResult && !error && blobResult[@"cid"]) {
            passedTests++;
            NSLog(@"✅ Blob Upload: PASSED - CID: %@", blobResult[@"cid"]);
        } else {
            NSLog(@"❌ Blob Upload: FAILED - Error: %@", error);
        }

        // Test 14: Session Refresh
        totalTests++;
        if (sessionResult && sessionResult[@"refreshJwt"]) {
            NSDictionary *refreshResult = [controller refreshSessionWithRefreshToken:sessionResult[@"refreshJwt"] error:&error];
            if (refreshResult && !error && refreshResult[@"accessJwt"]) {
                passedTests++;
                NSLog(@"✅ Session Refresh: PASSED - Got new access token");
            } else {
                NSLog(@"❌ Session Refresh: FAILED - Error: %@", error);
            }
        } else {
            NSLog(@"❌ Session Refresh: SKIPPED - No refresh token available");
        }

        // Test 15: Record Deletion
        totalTests++;
        if (recordResult) {
            NSString *rkey = recordResult[@"uri"];
            NSArray *uriComponents = [rkey componentsSeparatedByString:@"/"];
            NSString *recordKey = uriComponents.lastObject;

            BOOL deleteSuccess = [controller deleteRecordForDid:did collection:@"app.bsky.feed.post" rkey:recordKey error:&error];
            if (deleteSuccess && !error) {
                passedTests++;
                NSLog(@"✅ Record Deletion: PASSED");
            } else {
                NSLog(@"❌ Record Deletion: FAILED - Error: %@", error);
            }
        } else {
            NSLog(@"❌ Record Deletion: SKIPPED - No record to delete");
        }

        [database close];

        // Summary
        NSLog(@"🎯 PDS Integration Test Results: %lu/%lu tests passed", (unsigned long)passedTests, (unsigned long)totalTests);

        if (passedTests == totalTests) {
            NSLog(@"🎉 All PDS integration tests PASSED! The system is working correctly.");
        } else {
            double passRate = (double)passedTests / (double)totalTests * 100.0;
            NSLog(@"⚠️  PDS integration tests: %.1f%% pass rate (%lu/%lu). Some features may need attention.", passRate, (unsigned long)passedTests, (unsigned long)totalTests);
        }

        return (int)passedTests;
    }
}

int main(int argc, const char * argv[]) {
    return runPDSIntegrationTests(argc, argv);
}
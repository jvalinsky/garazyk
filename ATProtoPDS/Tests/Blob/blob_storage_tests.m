#import <Foundation/Foundation.h>
#import "Blob/BlobStorage.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"
#import "Core/CID.h"

/// Comprehensive tests for blob storage functionality
int runBlobStorageTests(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Running Blob Storage Tests");
        NSUInteger totalTests = 0;
        NSUInteger passedTests = 0;

        // Setup test database and storage
        NSError *setupError = nil;
        NSURL *testDBURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"test_blob_storage.db"]];
        NSURL *testStorageURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"test_blob_storage"]];

        // Clean up any existing test files
        [[NSFileManager defaultManager] removeItemAtURL:testDBURL error:nil];
        [[NSFileManager defaultManager] removeItemAtURL:testStorageURL error:nil];

        PDSDatabase *database = [PDSDatabase databaseAtURL:testDBURL];
        if (![database openWithError:&setupError]) {
            NSLog(@"❌ Failed to open test database: %@", setupError);
            return 1;
        }

        BlobStorage *blobStorage = [[BlobStorage alloc] initWithDatabase:database storageDirectory:testStorageURL];

        // Test 1: BlobStorage initialization
        totalTests++;
        if (blobStorage && [blobStorage.storageDirectory isEqual:testStorageURL] && blobStorage.database == database) {
            passedTests++;
            NSLog(@"✅ BlobStorage Initialization: PASSED");
        } else {
            NSLog(@"❌ BlobStorage Initialization: FAILED");
        }

        // Test 2: Basic blob storage setup
        totalTests++;
        NSString *testString = @"Hello, World! This is test blob data.";
        NSData *testData = [testString dataUsingEncoding:NSUTF8StringEncoding];
        if (testData && testData.length > 0) {
            passedTests++;
            NSLog(@"✅ Test Data Setup: PASSED");
        } else {
            NSLog(@"❌ Test Data Setup: FAILED");
        }

        // Test 3: Blob validation - valid image
        totalTests++;
        NSError *validationError = nil;
        NSData *validImageData = [@"fake-image-data" dataUsingEncoding:NSUTF8StringEncoding];
        BOOL isValid = [blobStorage validateBlob:validImageData mimeType:@"image/jpeg" error:&validationError];
        if (isValid) {
            passedTests++;
            NSLog(@"✅ Blob Validation (Valid): PASSED");
        } else {
            NSLog(@"❌ Blob Validation (Valid): FAILED - %@", validationError.localizedDescription);
        }

        // Test 4: Blob validation - invalid MIME type
        totalTests++;
        BOOL isInvalid = ![blobStorage validateBlob:validImageData mimeType:@"invalid/type" error:&validationError];
        if (isInvalid && validationError) {
            passedTests++;
            NSLog(@"✅ Blob Validation (Invalid MIME): PASSED");
        } else {
            NSLog(@"❌ Blob Validation (Invalid MIME): FAILED");
        }

        // Test 5: Blob validation - too large
        totalTests++;
        NSMutableData *largeData = [NSMutableData dataWithLength:6 * 1024 * 1024]; // 6MB > 5MB limit
        BOOL isTooLarge = ![blobStorage validateBlob:largeData mimeType:@"image/jpeg" error:&validationError];
        if (isTooLarge && validationError) {
            passedTests++;
            NSLog(@"✅ Blob Validation (Too Large): PASSED");
        } else {
            NSLog(@"❌ Blob Validation (Too Large): FAILED");
        }

        // Test 6: Blob upload
        totalTests++;
        NSString *testDID = @"did:web:test.example.com";
        CID *uploadedCID = [blobStorage uploadBlob:testData mimeType:@"text/plain" did:testDID error:&validationError];
        if (uploadedCID && uploadedCID.stringValue) {
            passedTests++;
            NSLog(@"✅ Blob Upload: PASSED (CID: %@)", uploadedCID.stringValue);
        } else {
            NSLog(@"❌ Blob Upload: FAILED - %@", validationError.localizedDescription);
        }

        // Test 7: Blob upload duplicate (should return same CID)
        totalTests++;
        if (uploadedCID) {
            CID *duplicateCID = [blobStorage uploadBlob:testData mimeType:@"text/plain" did:testDID error:&validationError];
            if (duplicateCID && [duplicateCID.stringValue isEqualToString:uploadedCID.stringValue]) {
                passedTests++;
                NSLog(@"✅ Blob Upload (Duplicate): PASSED");
            } else {
                NSLog(@"❌ Blob Upload (Duplicate): FAILED");
            }
        } else {
            NSLog(@"❌ Blob Upload (Duplicate): SKIPPED (previous upload failed)");
        }

        // Test 8: Blob retrieval
        totalTests++;
        if (uploadedCID) {
            NSData *retrievedData = [blobStorage getBlobWithCID:uploadedCID error:&validationError];
            if (retrievedData && [retrievedData isEqualToData:testData]) {
                passedTests++;
                NSLog(@"✅ Blob Retrieval: PASSED");
            } else {
                NSLog(@"❌ Blob Retrieval: FAILED - %@", validationError.localizedDescription);
            }
        } else {
            NSLog(@"❌ Blob Retrieval: SKIPPED (upload failed)");
        }

        // Test 9: Blob retrieval with wrong CID
        totalTests++;
        CID *wrongCID = [CID cidWithMultihash:[NSData dataWithBytes:(uint8_t[]){0x12, 0x20, 0x00, 0x01, 0x02} length:5] codec:0x70];
        if (wrongCID) {
            NSData *wrongData = [blobStorage getBlobWithCID:wrongCID error:&validationError];
            if (!wrongData) {
                passedTests++;
                NSLog(@"✅ Blob Retrieval (Not Found): PASSED");
            } else {
                NSLog(@"❌ Blob Retrieval (Not Found): FAILED");
            }
        } else {
            NSLog(@"❌ Blob Retrieval (Not Found): SKIPPED (CID creation failed)");
        }

        // Test 10: Blob listing
        totalTests++;
        NSArray *blobList = [blobStorage listBlobsForDID:testDID limit:10 cursor:nil error:&validationError];
        NSUInteger expectedCount = uploadedCID ? 1 : 0;
        if (blobList && blobList.count == expectedCount) {
            if (expectedCount == 1) {
                NSDictionary *blobInfo = blobList.firstObject;
                BOOL cidMatches = [blobInfo[@"cid"] isEqualToString:uploadedCID.stringValue];
                BOOL mimeTypeMatches = [blobInfo[@"mimeType"] isEqualToString:@"text/plain"];
                BOOL sizeMatches = [blobInfo[@"size"] isEqual:@(testData.length)];

                if (cidMatches && mimeTypeMatches && sizeMatches) {
                    passedTests++;
                    NSLog(@"✅ Blob Listing: PASSED");
                } else {
                    NSLog(@"❌ Blob Listing: FAILED");
                    NSLog(@"  Expected CID: %@", uploadedCID.stringValue);
                    NSLog(@"  Actual CID: %@", blobInfo[@"cid"]);
                    NSLog(@"  CID matches: %@", cidMatches ? @"YES" : @"NO");
                    NSLog(@"  MIME type matches: %@", mimeTypeMatches ? @"YES" : @"NO");
                    NSLog(@"  Size matches: %@", sizeMatches ? @"YES" : @"NO");
                }
            } else {
                passedTests++;
                NSLog(@"✅ Blob Listing: PASSED");
            }
        } else {
            NSLog(@"❌ Blob Listing: FAILED - Expected %lu blobs, got %lu", (unsigned long)expectedCount, (unsigned long)blobList.count);
        }

        // Test 11: Blob listing for non-existent DID
        totalTests++;
        NSArray *emptyList = [blobStorage listBlobsForDID:@"did:web:nonexistent.com" limit:10 cursor:nil error:&validationError];
        if (emptyList && emptyList.count == 0) {
            passedTests++;
            NSLog(@"✅ Blob Listing (Empty): PASSED");
        } else {
            NSLog(@"❌ Blob Listing (Empty): FAILED");
        }

        // Test 12: Blob deletion
        totalTests++;
        if (uploadedCID) {
            BOOL deleted = [blobStorage deleteBlobWithCID:uploadedCID did:testDID error:&validationError];
            if (deleted) {
                passedTests++;
                NSLog(@"✅ Blob Deletion: PASSED");
            } else {
                NSLog(@"❌ Blob Deletion: FAILED - %@", validationError.localizedDescription);
            }
        } else {
            NSLog(@"❌ Blob Deletion: SKIPPED (upload failed)");
        }

        // Test 13: Verify deletion - retrieval should fail
        totalTests++;
        if (uploadedCID) {
            NSData *deletedData = [blobStorage getBlobWithCID:uploadedCID error:&validationError];
            if (!deletedData) {
                passedTests++;
                NSLog(@"✅ Blob Deletion Verification: PASSED");
            } else {
                NSLog(@"❌ Blob Deletion Verification: FAILED");
            }
        } else {
            NSLog(@"❌ Blob Deletion Verification: SKIPPED (upload failed)");
        }

        // Test 14: Verify deletion - listing should be empty
        totalTests++;
        if (uploadedCID) {
            NSArray *afterDeleteList = [blobStorage listBlobsForDID:testDID limit:10 cursor:nil error:&validationError];
            if (afterDeleteList && afterDeleteList.count == 0) {
                passedTests++;
                NSLog(@"✅ Blob Deletion Listing Verification: PASSED");
            } else {
                NSLog(@"❌ Blob Deletion Listing Verification: FAILED");
            }
        } else {
            NSArray *afterDeleteList = [blobStorage listBlobsForDID:testDID limit:10 cursor:nil error:&validationError];
            if (afterDeleteList && afterDeleteList.count == 0) {
                passedTests++;
                NSLog(@"✅ Blob Deletion Listing Verification: PASSED");
            } else {
                NSLog(@"❌ Blob Deletion Listing Verification: FAILED");
            }
        }

        // Test 15: Blob upload with different DID
        totalTests++;
        NSString *otherDID = @"did:web:other.example.com";
        CID *otherCID = [blobStorage uploadBlob:testData mimeType:@"text/plain" did:otherDID error:&validationError];
        if (otherCID) {
            passedTests++;
            NSLog(@"✅ Blob Upload (Different DID): PASSED");
        } else {
            NSLog(@"❌ Blob Upload (Different DID): FAILED");
        }

        // Test 16: Blob isolation between DIDs
        totalTests++;
        NSArray *testDIDList = [blobStorage listBlobsForDID:testDID limit:10 cursor:nil error:&validationError];
        NSArray *otherDIDList = [blobStorage listBlobsForDID:otherDID limit:10 cursor:nil error:&validationError];
        if (testDIDList.count == 0 && otherDIDList.count == 1) {
            passedTests++;
            NSLog(@"✅ Blob DID Isolation: PASSED");
        } else {
            NSLog(@"❌ Blob DID Isolation: FAILED - testDID: %lu, otherDID: %lu",
                  (unsigned long)testDIDList.count, (unsigned long)otherDIDList.count);
        }

        // Cleanup
        [database close];
        [[NSFileManager defaultManager] removeItemAtURL:testDBURL error:nil];
        [[NSFileManager defaultManager] removeItemAtURL:testStorageURL error:nil];

        // Summary
        NSLog(@"🎯 Blob Storage Test Results: %lu/%lu tests passed", (unsigned long)passedTests, (unsigned long)totalTests);

        if (passedTests == totalTests) {
            NSLog(@"🎉 All blob storage tests PASSED! The blob storage system is working correctly.");
            return 0;
        } else {
            NSLog(@"⚠️  Some blob storage tests FAILED. Please review the implementation.");
            return 1;
        }
    }
}

int main(int argc, const char * argv[]) {
    return runBlobStorageTests(argc, argv);
}
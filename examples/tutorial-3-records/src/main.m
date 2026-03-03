#import <Foundation/Foundation.h>
#import "RecordService.h"
#import "RecordRepository.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 3: Record Operations");
        NSLog(@"==============================\n");
        
        // Initialize record service
        NSString *dbPath = @"./tutorial-data";
        RecordRepository *repo = [[RecordRepository alloc] initWithDatabasePath:dbPath];
        RecordService *service = [[RecordService alloc] initWithRepository:repo];
        
        NSString *did = @"did:plc:tutorial123";
        NSString *collection = @"app.bsky.feed.post";
        
        // Test 1: Create a record
        NSLog(@"Test 1: Creating a record...");
        NSString *rkey1 = [[NSUUID UUID] UUIDString];
        NSDictionary *value1 = @{
            @"text": @"Hello from Tutorial 3!",
            @"createdAt": @"2024-01-01T00:00:00Z"
        };
        
        NSError *error = nil;
        NSDictionary *result1 = [service createRecord:collection
                                                 rkey:rkey1
                                                value:value1
                                               forDid:did
                                                error:&error];
        
        if (result1) {
            NSLog(@"✓ Record created:");
            NSLog(@"  URI: %@", result1[@"uri"]);
            NSLog(@"  CID: %@\n", result1[@"cid"]);
        } else {
            NSLog(@"✗ Failed to create record: %@\n", error);
            return 1;
        }
        
        // Test 2: Create another record
        NSLog(@"Test 2: Creating another record...");
        NSString *rkey2 = [[NSUUID UUID] UUIDString];
        NSDictionary *value2 = @{
            @"text": @"This is my second post!",
            @"createdAt": @"2024-01-01T01:00:00Z"
        };
        
        NSDictionary *result2 = [service createRecord:collection
                                                 rkey:rkey2
                                                value:value2
                                               forDid:did
                                                error:&error];
        
        if (result2) {
            NSLog(@"✓ Record created:");
            NSLog(@"  URI: %@", result2[@"uri"]);
            NSLog(@"  CID: %@\n", result2[@"cid"]);
        } else {
            NSLog(@"✗ Failed to create record: %@\n", error);
            return 1;
        }
        
        // Test 3: Get a record
        NSLog(@"Test 3: Retrieving first record...");
        NSString *uri1 = result1[@"uri"];
        NSDictionary *retrieved = [service getRecord:uri1 forDid:did error:&error];
        
        if (retrieved) {
            NSLog(@"✓ Record retrieved:");
            NSLog(@"  URI: %@", retrieved[@"uri"]);
            NSLog(@"  CID: %@", retrieved[@"cid"]);
            NSLog(@"  Value: %@\n", retrieved[@"value"]);
        } else {
            NSLog(@"✗ Failed to retrieve record: %@\n", error);
            return 1;
        }
        
        // Test 4: List records
        NSLog(@"Test 4: Listing all records...");
        NSArray *records = [service listRecords:collection forDid:did limit:50 error:&error];
        
        if (records) {
            NSLog(@"✓ Found %lu records:", (unsigned long)records.count);
            for (NSDictionary *record in records) {
                NSLog(@"  - %@", record[@"uri"]);
                NSLog(@"    Text: %@", record[@"value"][@"text"]);
            }
            NSLog(@"");
        } else {
            NSLog(@"✗ Failed to list records: %@\n", error);
            return 1;
        }
        
        // Test 5: Delete a record
        NSLog(@"Test 5: Deleting first record...");
        BOOL deleted = [service deleteRecord:uri1 forDid:did error:&error];
        
        if (deleted) {
            NSLog(@"✓ Record deleted: %@\n", uri1);
        } else {
            NSLog(@"✗ Failed to delete record: %@\n", error);
            return 1;
        }
        
        // Test 6: Verify deletion
        NSLog(@"Test 6: Verifying deletion...");
        NSDictionary *shouldBeNil = [service getRecord:uri1 forDid:did error:&error];
        
        if (!shouldBeNil) {
            NSLog(@"✓ Record successfully deleted (not found)\n");
        } else {
            NSLog(@"✗ Record still exists after deletion\n");
            return 1;
        }
        
        // Test 7: List records again
        NSLog(@"Test 7: Listing records after deletion...");
        NSArray *remainingRecords = [service listRecords:collection forDid:did limit:50 error:&error];
        
        if (remainingRecords) {
            NSLog(@"✓ Found %lu remaining records:", (unsigned long)remainingRecords.count);
            for (NSDictionary *record in remainingRecords) {
                NSLog(@"  - %@", record[@"uri"]);
                NSLog(@"    Text: %@", record[@"value"][@"text"]);
            }
            NSLog(@"");
        } else {
            NSLog(@"✗ Failed to list records: %@\n", error);
            return 1;
        }
        
        NSLog(@"==============================");
        NSLog(@"All tests passed! ✓");
        NSLog(@"Database location: %@", dbPath);
    }
    
    return 0;
}

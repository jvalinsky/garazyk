#import <Foundation/Foundation.h>
#import "TutorialBlobStore.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 7: Blob Storage");
        NSLog(@"========================\n");

        // Setup data directory
        NSString *dataDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tutorial-7-blobs"];
        [[NSFileManager defaultManager] removeItemAtPath:dataDir error:nil];

        TutorialBlobStore *blobStore = [[TutorialBlobStore alloc] initWithDataDirectory:dataDir];
        NSString *did = @"did:web:localhost:~alice";

        NSError *error = nil;

        // ============================================================
        // 1. Upload a blob
        // ============================================================
        NSLog(@"1. Upload a blob");
        NSLog(@"-----------------");

        NSString *textContent = @"Hello from Tutorial 7! This is a text blob.";
        NSData *textData = [textContent dataUsingEncoding:NSUTF8StringEncoding];
        NSString *textCid = [blobStore putBlob:textData forDID:did mimeType:@"text/plain" error:&error];
        if (textCid) {
            NSLog(@"Uploaded text blob: %@", textCid);
        } else {
            NSLog(@"Upload failed: %@", error.localizedDescription);
            return 1;
        }

        // Upload an image blob (simulated)
        NSMutableData *imageData = [NSMutableData dataWithLength:50 * 1024]; // 50KB
        arc4random_buf(imageData.mutableBytes, imageData.length);
        NSString *imageCid = [blobStore putBlob:imageData forDID:did mimeType:@"image/png" error:&error];
        if (imageCid) {
            NSLog(@"Uploaded image blob: %@\n", imageCid);
        } else {
            NSLog(@"Image upload failed: %@\n", error.localizedDescription);
        }

        // ============================================================
        // 2. Retrieve a blob
        // ============================================================
        NSLog(@"2. Retrieve a blob");
        NSLog(@"-------------------");

        NSString *outMime = nil;
        NSUInteger outSize = 0;
        NSData *retrieved = [blobStore getBlob:textCid forDID:did outMimeType:&outMime outSize:&outSize error:&error];
        if (retrieved) {
            NSString *retrievedText = [[NSString alloc] initWithData:retrieved encoding:NSUTF8StringEncoding];
            NSLog(@"Retrieved blob: %@ (%lu bytes, %@)", textCid, (unsigned long)outSize, outMime);
            NSLog(@"Content: %@\n", retrievedText);
        } else {
            NSLog(@"Retrieval failed: %@\n", error.localizedDescription);
        }

        // ============================================================
        // 3. Range request (partial content)
        // ============================================================
        NSLog(@"3. Range request");
        NSLog(@"-----------------");

        NSRange range = NSMakeRange(0, 5); // First 5 bytes
        NSData *partial = [blobStore getBlob:textCid forDID:did range:range outMimeType:&outMime outSize:&outSize error:&error];
        if (partial) {
            NSString *partialText = [[NSString alloc] initWithData:partial encoding:NSUTF8StringEncoding];
            NSLog(@"Partial read (bytes 0-4): \"%@\" (total size: %lu)\n", partialText, (unsigned long)outSize);
        }

        // ============================================================
        // 4. Content-addressed deduplication
        // ============================================================
        NSLog(@"4. Content-addressed deduplication");
        NSLog(@"----------------------------------");

        // Upload the same content again — should get the same CID
        NSString *duplicateCid = [blobStore putBlob:textData forDID:did mimeType:@"text/plain" error:&error];
        if ([duplicateCid isEqualToString:textCid]) {
            NSLog(@"Same content = same CID: %@ (deduplication works)\n", textCid);
        } else {
            NSLog(@"CIDs differ: %@ vs %@\n", textCid, duplicateCid);
        }

        // ============================================================
        // 5. Size limits
        // ============================================================
        NSLog(@"5. Size limits");
        NSLog(@"---------------");

        // Try to upload a blob that exceeds the size limit
        blobStore.maxBlobSize = 1024; // 1KB limit for testing
        NSMutableData *bigData = [NSMutableData dataWithLength:2048]; // 2KB
        NSString *bigCid = [blobStore putBlob:bigData forDID:did mimeType:@"application/octet-stream" error:&error];
        if (!bigCid) {
            NSLog(@"Correctly rejected oversized blob: %@\n", error.localizedDescription);
        }
        blobStore.maxBlobSize = 1024 * 1024; // Reset to 1MB

        // ============================================================
        // 6. List blobs
        // ============================================================
        NSLog(@"6. List blobs");
        NSLog(@"--------------");

        NSArray *blobs = [blobStore listBlobsForDID:did limit:50 cursor:nil error:&error];
        if (blobs) {
            NSLog(@"Found %lu blobs for %@:", (unsigned long)blobs.count, did);
            for (NSDictionary *blob in blobs) {
                NSLog(@"  CID: %@  MIME: %@  Size: %@",
                      blob[@"cid"], blob[@"mimeType"], blob[@"size"]);
            }
            NSLog(@"");
        }

        // ============================================================
        // 7. Delete a blob
        // ============================================================
        NSLog(@"7. Delete a blob");
        NSLog(@"-----------------");

        BOOL deleted = [blobStore deleteBlob:imageCid forDID:did error:&error];
        if (deleted) {
            NSLog(@"Deleted blob: %@", imageCid);
        }

        // Verify deletion
        NSData *shouldNotExist = [blobStore getBlob:imageCid forDID:did outMimeType:nil outSize:nil error:nil];
        if (!shouldNotExist) {
            NSLog(@"Blob correctly removed after deletion\n");
        }

        // ============================================================
        // 8. Cross-DID isolation
        // ============================================================
        NSLog(@"8. Cross-DID isolation");
        NSLog(@"----------------------");

        NSString *otherDid = @"did:web:localhost:~bob";
        NSData *crossDidBlob = [blobStore getBlob:textCid forDID:otherDid outMimeType:nil outSize:nil error:nil];
        if (!crossDidBlob) {
            NSLog(@"Bob cannot access Alice's blob (correct isolation)\n");
        }

        NSLog(@"========================");
        NSLog(@"Tutorial completed!");
        NSLog(@"Key concepts:");
        NSLog(@"  - CID-based content addressing (same content = same CID)");
        NSLog(@"  - MIME type validation and storage");
        NSLog(@"  - Size limits per blob and per DID quota");
        NSLog(@"  - Range requests for partial content");
        NSLog(@"  - DID-scoped access control");
    }

    return 0;
}

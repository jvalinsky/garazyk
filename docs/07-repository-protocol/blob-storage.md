# Blob Storage

## Overview

Blob storage manages binary files (images, videos, etc.) associated with records. Blobs are content-addressed using CIDs and stored separately from records.

## Blob Lifecycle

```
1. Upload
   ├─ Receive binary data
   ├─ Generate CID
   ├─ Store in blob storage
   └─ Return CID to client

2. Reference
   ├─ Include CID in record
   ├─ Store record
   └─ Link blob to record

3. Retrieval
   ├─ Get record
   ├─ Extract blob CID
   ├─ Retrieve blob by CID
   └─ Return to client

4. Deletion
   ├─ Delete record
   ├─ Check if blob referenced elsewhere
   ├─ If not referenced, delete blob
   └─ Free storage
```

## Blob Storage Backend

```objc
@interface BlobStorage : NSObject

// Initialization
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool 
                            provider:(id<PDSBlobProvider>)provider;

// Upload and retrieval
- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error;

- (nullable NSData *)getBlobWithCID:(CID *)cid 
                                did:(nullable NSString *)did 
                               error:(NSError **)error;

// Deletion
- (BOOL)deleteBlobWithCID:(CID *)cid 
                      did:(NSString *)did 
                     error:(NSError **)error;

// Listing
- (NSArray<PDSDatabaseBlob *> *)listBlobsForDID:(NSString *)did
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error;

@end
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 1-50)

## File-Based Storage

```objc
@interface FileBasedBlobStorage : NSObject <BlobStorage>

- (instancetype)initWithDirectory:(NSString *)directory;

@end
```

### Directory Structure

```
${blobDirectory}/
├── ${cidPrefix2}/
│   ├── ${cidPrefix4}/
│   │   ├── ${cid}.blob
│   │   └── ${cid}.meta
│   └── ...
└── ...
```

## Storing Blobs

```objc
// 1. Validate the blob
NSError *error = nil;
if (![blobStorage validateBlob:blobData mimeType:@"image/jpeg" error:&error]) {
    NSLog(@"Blob validation failed: %@", error);
    return;
}

// 2. Upload blob (computes CID internally)
CID *cid = [blobStorage uploadBlob:blobData
                          mimeType:@"image/jpeg"
                               did:userDid
                             error:&error];

if (!cid) {
    NSLog(@"Upload failed: %@", error);
    return;
}

// 3. Use CID in record
NSDictionary *metadata = @{
    @"cid": cid.stringValue,
    @"mimeType": @"image/jpeg",
    @"size": @(blobData.length)
};

NSLog(@"Blob stored with CID: %@", cid.stringValue);
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 35-85)

## Blob References

Blobs are referenced in records using embeds:

```json
{
  "text": "Check out this image!",
  "embed": {
    "$type": "app.bsky.embed.image",
    "image": {
      "cid": "bafy2bzaced...",
      "mimeType": "image/jpeg",
      "size": 102400
    }
  }
}
```

## Garbage Collection

Blobs without references are deleted:

```objc
// 1. List all blobs for user
NSError *error = nil;
NSArray<PDSDatabaseBlob *> *allBlobs = [blobStorage listBlobsForDID:userDid
                                                               limit:1000
                                                              cursor:nil
                                                               error:&error];

// 2. Check each blob for references
for (PDSDatabaseBlob *blob in allBlobs) {
    CID *cid = [CID cidFromBytes:blob.cid];
    
    // Check if blob is referenced in any records
    NSArray *references = [recordService findReferencesToBlob:cid forDid:userDid];
    
    if (references.count == 0) {
        // 3. Delete unreferenced blob
        BOOL success = [blobStorage deleteBlobWithCID:cid 
                                                  did:userDid 
                                                 error:&error];
        
        if (success) {
            NSLog(@"Deleted unreferenced blob: %@", cid.stringValue);
        }
    }
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 120-150)

## Blob Quotas

Users have storage quotas:

```sql
CREATE TABLE blob_quotas (
    did TEXT PRIMARY KEY,
    quota_bytes INTEGER,
    used_bytes INTEGER,
    FOREIGN KEY (did) REFERENCES accounts(did)
);
```

### Enforcing Quotas

```objc
// 1. Check quota before upload
NSError *error = nil;
NSUInteger usedBytes = [blobStorage getUsedBlobStorage:userDid];
NSUInteger quotaBytes = [blobStorage getBlobQuota:userDid];

if (usedBytes + blobData.length > quotaBytes) {
    [XrpcErrorHelper setValidationError:response message:@"Blob quota exceeded"];
    return;
}

// 2. Upload blob
CID *cid = [blobStorage uploadBlob:blobData
                          mimeType:mimeType
                               did:userDid
                             error:&error];

if (!cid) {
    [XrpcErrorHelper setInternalServerError:response];
    return;
}

// 3. Update usage (done automatically by uploadBlob)
NSLog(@"Blob uploaded. Used: %lu / %lu bytes", 
      (unsigned long)(usedBytes + blobData.length), 
      (unsigned long)quotaBytes);
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 35-85)

## Blob Validation

## Blob Validation

### MIME Type Validation

```objc
// 1. Validate MIME type
MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];
NSError *mimeError = nil;

if (![validator isValidMimeType:mimeType error:&mimeError]) {
    NSLog(@"Invalid MIME type: %@", mimeError);
    return NO;
}

if (![validator isSupportedMimeType:mimeType error:&mimeError]) {
    NSLog(@"Unsupported MIME type: %@", mimeError);
    return NO;
}

// 2. Validate magic bytes
if (![validator validateMagicNumbers:blobData forMimeType:mimeType error:&mimeError]) {
    NSLog(@"Magic number mismatch: %@", mimeError);
    return NO;
}
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 180-220)

### Size Validation

```objc
// 1. Check size limits
MimeTypeValidator *validator = [MimeTypeValidator sharedValidator];
NSError *sizeError = nil;

if (![validator validateSize:blobData.length forMimeType:mimeType error:&sizeError]) {
    NSLog(@"Size validation failed: %@", sizeError);
    return NO;
}

// 2. Check minimum size
if (blobData.length == 0) {
    NSLog(@"Blob is empty");
    return NO;
}

NSLog(@"Blob size valid: %lu bytes", (unsigned long)blobData.length);
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 180-220)

## Best Practices

1. **Storage**
   - Use content addressing (CID)
   - Deduplicate identical blobs
   - Implement garbage collection
   - Monitor storage usage

2. **Validation**
   - Validate MIME types
   - Check magic bytes
   - Enforce size limits
   - Scan for malware

3. **Performance**
   - Use streaming for large blobs
   - Cache frequently accessed blobs
   - Implement CDN for distribution
   - Monitor access patterns

4. **Security**
   - Validate file content
   - Prevent path traversal
   - Implement access controls
   - Log blob operations

## Common Patterns

### Uploading a Blob

```objc
// 1. Receive blob
NSData *blobData = request.body;
NSString *mimeType = [request headerForName:@"Content-Type"];

// 2. Validate
NSError *error = nil;
if (![blobStorage validateBlob:blobData mimeType:mimeType error:&error]) {
    [XrpcErrorHelper setValidationError:response message:error.localizedDescription];
    return;
}

// 3. Upload
CID *cid = [blobStorage uploadBlob:blobData
                          mimeType:mimeType
                               did:userDid
                             error:&error];

if (!cid) {
    [XrpcErrorHelper setInternalServerError:response];
    return;
}

// 4. Return CID
NSDictionary *blob = @{
    @"cid": cid.stringValue,
    @"mimeType": mimeType,
    @"size": @(blobData.length)
};

response.statusCode = 200;
response.body = [NSJSONSerialization dataWithJSONObject:blob options:0 error:nil];
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 35-85)

### Creating a Post with Image

```objc
// 1. Upload image
NSError *error = nil;
CID *imageCid = [blobStorage uploadBlob:imageData
                               mimeType:@"image/jpeg"
                                    did:userDid
                                  error:&error];

if (!imageCid) {
    NSLog(@"Image upload failed: %@", error);
    return;
}

// 2. Create post with image embed
NSDictionary *post = @{
    @"text": @"Check out this image!",
    @"embed": @{
        @"$type": @"app.bsky.embed.image",
        @"image": @{
            @"cid": imageCid.stringValue,
            @"mimeType": @"image/jpeg",
            @"size": @(imageData.length)
        }
    }
};

// 3. Encode and store post
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:post error:&error];
if (!cborData) {
    NSLog(@"Encoding failed: %@", error);
    return;
}

NSData *hash = [CID sha256Digest:cborData];
CID *postCid = [CID cidWithDigest:hash codec:0x71];

NSLog(@"Post created with image: %@", postCid.stringValue);
```

**Source:** `ATProtoPDS/Sources/Blob/BlobStorage.m` (lines 35-85); `ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m` (lines 8-20)

## See Also

**Basic Topics:**
- [Blob Service](../03-application-layer/blob-service) — Blob service layer
- [CID and Hashing](./cid-and-hashing) — Content addressing
- [Repository Basics](./repository-basics) — Repository structure

**Advanced Topics:**
- [Blob Lifecycle](./blob-lifecycle) — Upload/download/deletion
- [Blob Optimization](./blob-optimization) — Chunking and caching
- [Blob Garbage Collection](./blob-garbage-collection) — Cleanup strategies
- [Blob Quotas](./blob-quotas) — Size limits and enforcement

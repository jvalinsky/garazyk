# Blob Service

## Overview

The `PDSBlobService` manages binary blob storage and retrieval for ATProto repositories. It handles blob uploads, downloads, metadata management, and deletion with content-addressed storage using CIDs.

### Why This Service Matters

Blobs enable rich media in ATProto - images, videos, audio, and other binary data. The Blob Service ensures:

- **Content Addressing**: Each blob has a unique CID based on its content, enabling deduplication and integrity verification
- **Efficient Storage**: Large files can be streamed without loading into memory
- **Quota Management**: Per-user storage limits prevent abuse
- **Immutability**: Once uploaded, blobs cannot be modified (only deleted), ensuring data integrity

Understanding blob management is essential for implementing media-rich applications like social networks, photo sharing, or document storage on ATProto.

## When to Use This Service

### Use Blob Service When:

- **Uploading media**: Images, videos, audio files for posts or profiles
- **Storing documents**: PDFs, text files, or other binary data
- **Managing avatars and banners**: Profile images that need to be referenced in records
- **Implementing embeds**: Media that will be embedded in posts or other records

### Don't Use Blob Service For:

- **Text data**: Use records for structured text (posts, profiles, etc.)
- **Small metadata**: Store in record fields rather than as separate blobs
- **Temporary data**: Blobs are permanent until explicitly deleted
- **Frequently changing data**: Blobs are immutable; use records for mutable data

## Responsibilities

- Blob upload and CID generation
- Blob retrieval by CID
- Blob metadata management
- Blob listing with pagination
- Blob deletion
- File-backed streaming support
- Storage backend abstraction

## Architecture

```
┌──────────────────────────────────────────┐
│   XRPC Blob Endpoints                    │
│  (com.atproto.repo.uploadBlob)           │
│  (com.atproto.sync.getBlob)              │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   PDSBlobService                         │
│  - uploadBlob()                          │
│  - getBlob()                             │
│  - getBlobWithCID()                      │
│  - listBlobs()                           │
│  - deleteBlob()                          │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌──▼──────────────┐
│ BlobStorage      │  │ CID Generation  │
│ (File/Memory)    │  │ (SHA-256)       │
└──────────────────┘  └──────────────────┘
        │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ PDSDatabasePool     │
        │ (Blob Metadata)     │
        └─────────────────────┘
```

## Key Methods

### Upload Blob

```objc
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                              forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                               error:(NSError **)error;
```

Uploads a blob and returns its CID and metadata.

**Parameters:**
- `blobData`: Binary blob data
- `did`: Repository owner DID
- `mimeType`: MIME type (e.g., "image/jpeg")
- `error`: Error pointer for failure details

**Returns:** Dictionary with CID, size, and metadata or nil on failure

**Implementation pattern (from PDSBlobService.m lines 30-60):**

The service uploads the blob to storage, generates a CID, and returns metadata:

```objc
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                              forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                               error:(NSError **)error {

    CID *cid = [self.blobStorage uploadBlob:blobData mimeType:mimeType did:did error:error];
    if (!cid) {
        return nil;
    }
    
    NSString *cidString = cid.stringValue;

    return @{
        @"blob": @{
            @"$type": @"blob",
            @"ref": @{@"$link": cidString},
            @"mimeType": mimeType,
            @"size": @(blobData.length)
        }
    };
}
```

**Example usage:**
```objc
NSData *imageData = [NSData dataWithContentsOfFile:@"/path/to/image.jpg"];

NSError *error = nil;
NSDictionary *blob = [blobService uploadBlob:imageData
                                     forDid:@"did:plc:user123"
                                   mimeType:@"image/jpeg"
                                      error:&error];

if (blob) {
    NSString *cid = blob[@"blob"][@"ref"][@"$link"];
    NSNumber *size = blob[@"blob"][@"size"];
    NSString *mimeType = blob[@"blob"][@"mimeType"];
}
```

### Get Blob

```objc
- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;
```

Retrieves blob data by CID.

**Parameters:**
- `cid`: Content identifier (binary)
- `did`: Repository owner DID
- `error`: Error pointer for failure details

**Returns:** Blob data or nil if not found

**Implementation pattern (from PDSBlobService.m lines 20-30):**

The service retrieves the blob from storage:

```objc
- (nullable NSData *)getBlob:(NSData *)cidData forDid:(NSString *)did error:(NSError **)error {
    CID *cid = [CID cidFromBytes:cidData];
    if (!cid) return nil;
    return [self.blobStorage getBlobWithCID:cid did:did error:error];
}
```

**Example usage:**
```objc
NSError *error = nil;
NSData *blobData = [blobService getBlob:cidData
                                forDid:@"did:plc:user123"
                                 error:&error];

if (blobData) {
    // Write to file or process
    [blobData writeToFile:@"/tmp/blob.jpg" atomically:YES];
}
```

### Get Blob with CID String

```objc
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                       did:(NSString *)did
                                    error:(NSError **)error;
```

Retrieves blob metadata by CID string.

**Parameters:**
- `cidString`: CID as string (e.g., "bafy...")
- `did`: Repository owner DID
- `error`: Error pointer for failure details

**Returns:** Dictionary with metadata or nil if not found

**Implementation pattern (from PDSBlobService.m lines 60-90):**

The service retrieves blob metadata from storage:

```objc
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                       did:(NSString *)did
                                     error:(NSError **)error {

    CID *cid = [CID cidFromString:cidString];
    if (!cid) {
        if (error) *error = [NSError errorWithDomain:@"PDSController" code:1003
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return nil;
    }

    NSData *blobData = [self.blobStorage getBlobWithCID:cid did:did error:error];
    if (!blobData) return nil;

    PDSDatabaseBlob *metadata = [self.blobStorage getBlobMetadataWithCID:cid.stringValue did:did error:nil];
    NSString *mimeType = metadata.mimeType ?: @"application/octet-stream";
    NSNumber *blobSize = metadata ? @(metadata.size) : nil;

    return @{
        @"blob": blobData,
        @"mimeType": mimeType,
        @"size": blobSize ?: @(blobData.length)
    };
}
```

**Example usage:**
```objc
NSError *error = nil;
NSDictionary *metadata = [blobService getBlobWithCID:@"bafy2bzaced..."
                                                 did:@"did:plc:user123"
                                              error:&error];

if (metadata) {
    NSNumber *size = metadata[@"size"];
    NSString *mimeType = metadata[@"mimeType"];
}
```

### Get Blob Stream

```objc
- (nullable NSDictionary *)getBlobStreamWithCID:(NSString *)cid
                                            did:(NSString *)did
                                          error:(NSError **)error;
```

Gets file-backed streaming metadata for a blob when available.

**Parameters:**
- `cid`: CID as string
- `did`: Repository owner DID
- `error`: Error pointer for failure details

**Returns:** Dictionary with stream metadata or nil

**Example:**
```objc
NSError *error = nil;
NSDictionary *stream = [blobService getBlobStreamWithCID:@"bafy2bzaced..."
                                                     did:@"did:plc:user123"
                                                   error:&error];

if (stream) {
    NSString *filePath = stream[@"path"];
    NSNumber *size = stream[@"size"];
    // Stream from file instead of loading into memory
}
```

### List Blobs

```objc
- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error;
```

Lists blobs for a DID with pagination.

**Parameters:**
- `did`: Repository owner DID
- `limit`: Maximum blobs to return
- `cursor`: Pagination cursor from previous response
- `error`: Error pointer for failure details

**Returns:** Array of blob metadata or nil on failure

**Example:**
```objc
NSError *error = nil;
NSArray *blobs = [blobService listBlobsForDID:@"did:plc:user123"
                                        limit:50
                                       cursor:nil
                                        error:&error];

for (NSDictionary *blob in blobs) {
    NSString *cid = blob[@"cid"];
    NSNumber *size = blob[@"size"];
    NSString *mimeType = blob[@"mimeType"];
}
```

### Delete Blob

```objc
- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error;
```

Deletes a blob by CID.

**Parameters:**
- `cid`: CID as string
- `did`: Repository owner DID
- `error`: Error pointer for failure details

**Returns:** YES on success, NO on failure

**Example:**
```objc
NSError *error = nil;
BOOL deleted = [blobService deleteBlobWithCID:@"bafy2bzaced..."
                                          did:@"did:plc:user123"
                                         error:&error];
```

## Storage Backend

The service uses a pluggable `BlobStorage` backend:

```objc
@property (nonatomic, strong) BlobStorage *blobStorage;
```

Backends can implement:
- File-based storage (disk)
- Memory-based storage (testing)
- Cloud storage (S3, etc.)

## CID Generation

Blobs are content-addressed using CIDv1 with SHA-256:

```
CID = CIDv1(sha256(blob_data))
```

This ensures:
- Deduplication (same content = same CID)
- Integrity verification
- Immutability

## Metadata Storage

Blob metadata is stored in the database:

| Field | Type | Purpose |
|-------|------|---------|
| cid | string | Content identifier |
| did | string | Repository owner |
| size | integer | Blob size in bytes |
| mimeType | string | MIME type |
| createdAt | timestamp | Upload time |
| hash | binary | SHA-256 hash |

## Error Handling

Common error scenarios:

| Error | Cause | Handling |
|-------|-------|----------|
| Blob too large | Exceeds size limit | Return 413 |
| Invalid MIME type | Unsupported type | Return 400 |
| Not found | CID doesn't exist | Return 404 |
| Storage error | Backend failure | Return 500 |
| Unauthorized | DID mismatch | Return 403 |

## Common Pitfalls and Troubleshooting

### Pitfall 1: Blob Size Limits

**Problem**: Large blob uploads fail or cause memory issues.

**Why it happens**: Loading entire blobs into memory can exhaust available RAM.

**Solution**: Use streaming for large files and enforce size limits:
```objc
// Check size before upload
NSUInteger maxBlobSize = 5 * 1024 * 1024; // 5 MB
if (blobData.length > maxBlobSize) {
    *error = [ATProtoError errorWithCode:ATProtoErrorCodeBlobTooLarge
                                 message:@"Blob exceeds maximum size"];
    return nil;
}

// For very large files, use streaming
NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:filePath];
[self uploadBlobFromStream:stream mimeType:mimeType forDid:did error:&error];
```

### Pitfall 2: MIME Type Validation

**Problem**: Malicious files uploaded with incorrect MIME types.

**Why it happens**: Trusting client-provided MIME types without verification.

**Solution**: Validate MIME types against file content:
```objc
- (NSString *)detectMIMEType:(NSData *)data {
    // Check magic bytes
    uint8_t bytes[12];
    [data getBytes:&bytes length:MIN(12, data.length)];
    
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return @"image/jpeg";
    }
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return @"image/png";
    }
    // PDF
    if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
        return @"application/pdf";
    }
    
    return @"application/octet-stream";
}

// Verify MIME type matches content
NSString *detectedType = [self detectMIMEType:blobData];
if (![detectedType isEqualToString:providedMimeType]) {
    PDS_LOG_WARN(@"MIME type mismatch: provided=%@, detected=%@", 
                 providedMimeType, detectedType);
    // Use detected type or reject upload
}
```

### Pitfall 3: Orphaned Blobs

**Problem**: Blobs remain in storage after records are deleted, wasting space.

**Why it happens**: No automatic garbage collection for unreferenced blobs.

**Solution**: Implement blob garbage collection:
```objc
- (void)garbageCollectBlobsForDid:(NSString *)did {
    // 1. Get all blob CIDs from records
    NSSet *referencedCIDs = [self getAllBlobCIDsFromRecords:did];
    
    // 2. Get all stored blobs
    NSArray *storedBlobs = [blobService listBlobsForDID:did limit:1000 cursor:nil error:nil];
    
    // 3. Delete unreferenced blobs
    for (NSDictionary *blob in storedBlobs) {
        NSString *cid = blob[@"cid"];
        if (![referencedCIDs containsObject:cid]) {
            NSError *error = nil;
            [blobService deleteBlobWithCID:cid did:did error:&error];
            if (!error) {
                PDS_LOG_INFO(@"Garbage collected blob: %@", cid);
            }
        }
    }
}
```

### Pitfall 4: CID Collisions

**Problem**: Different blobs appear to have the same CID.

**Why it happens**: Hash collisions (extremely rare) or implementation bugs.

**Solution**: Verify CID generation and handle collisions:
```objc
- (CID *)generateCIDForBlob:(NSData *)data error:(NSError **)error {
    // Generate SHA-256 hash
    NSData *hash = [self sha256Hash:data];
    
    // Create CIDv1 with raw codec
    CID *cid = [CID cidWithVersion:1
                            codec:CIDCodecRaw
                             hash:hash
                        hashType:CIDHashTypeSHA256];
    
    // Verify CID is unique (check if blob already exists)
    NSData *existingBlob = [self.blobStorage getBlobWithCID:cid did:did error:nil];
    if (existingBlob) {
        // Verify content matches
        if ([existingBlob isEqualToData:data]) {
            // Same content, deduplication working correctly
            PDS_LOG_DEBUG(@"Blob already exists with CID: %@", cid.stringValue);
        } else {
            // Hash collision (should never happen with SHA-256)
            PDS_LOG_ERROR(@"CID collision detected: %@", cid.stringValue);
            if (error) {
                *error = [NSError errorWithDomain:@"BlobService"
                                             code:500
                                         userInfo:@{NSLocalizedDescriptionKey: @"CID collision"}];
            }
            return nil;
        }
    }
    
    return cid;
}
```

### Troubleshooting Guide

#### Issue: "Blob not found" for recently uploaded blob

**Symptoms**: Upload succeeds but immediate retrieval fails.

**Possible causes**:
1. Asynchronous storage backend
2. Caching issues
3. DID mismatch

**Diagnosis**:
```objc
// Verify upload completed
NSDictionary *uploadResult = [blobService uploadBlob:data
                                             forDid:did
                                           mimeType:mimeType
                                              error:&error];
NSString *cid = uploadResult[@"blob"][@"ref"][@"$link"];
PDS_LOG_DEBUG(@"Uploaded blob CID: %@", cid);

// Immediate retrieval
NSData *retrieved = [blobService getBlob:[cid dataUsingEncoding:NSUTF8StringEncoding]
                                  forDid:did
                                   error:&error];
PDS_LOG_DEBUG(@"Retrieved blob: %@", retrieved ? @"YES" : @"NO");

// Check storage backend directly
BOOL exists = [self.blobStorage blobExistsWithCID:cid did:did];
PDS_LOG_DEBUG(@"Blob exists in storage: %d", exists);
```

#### Issue: Memory exhaustion during blob operations

**Symptoms**: Application crashes or becomes unresponsive when handling blobs.

**Possible causes**:
1. Loading large blobs into memory
2. Not releasing blob data
3. Concurrent blob operations

**Diagnosis**:
```objc
// Monitor memory usage
- (void)logMemoryUsage {
    struct task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(),
                                   TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &size);
    if (kerr == KERN_SUCCESS) {
        NSUInteger memoryMB = info.resident_size / (1024 * 1024);
        PDS_LOG_DEBUG(@"Memory usage: %lu MB", memoryMB);
    }
}

// Use autorelease pools for batch operations
for (NSString *cid in blobCIDs) {
    @autoreleasepool {
        NSData *blob = [blobService getBlob:cid forDid:did error:nil];
        [self processBlob:blob];
        // blob released at end of pool
    }
}
```

## Best Practices

1. **Upload Validation**
   - Validate MIME type against file content (magic bytes)
   - Check blob size limits before upload (5-10 MB typical)
   - Verify DID ownership before allowing upload
   - Rate limit uploads per user (e.g., 100 MB per hour)
   - Scan for malware in uploaded content

2. **Storage Management**
   - Use file-backed storage for large blobs (> 1 MB)
   - Implement garbage collection for orphaned blobs
   - Monitor storage usage per user and globally
   - Set size quotas per user (e.g., 1 GB total)
   - Archive or compress old blobs

3. **Performance**
   - Use streaming for large downloads (don't load into memory)
   - Cache frequently accessed blobs (avatars, popular images)
   - Implement CDN for blob distribution in production
   - Use compression where appropriate (gzip for text, optimize images)
   - Batch blob operations to reduce overhead

4. **Security**
   - Validate blob content (magic bytes) to prevent file type spoofing
   - Scan for malware and malicious content
   - Implement access controls (verify DID ownership)
   - Log blob operations for audit trails
   - Use HTTPS for blob transfers
   - Sanitize filenames and metadata

5. **Reliability**
   - Verify CID after upload (recompute and compare)
   - Implement retry logic for failed uploads
   - Use checksums to detect corruption
   - Backup blob storage regularly
   - Monitor storage backend health

## Common Patterns

### Uploading an Image

```objc
// 1. Read image file
NSData *imageData = [NSData dataWithContentsOfFile:imagePath];

// 2. Upload blob
NSError *error = nil;
NSDictionary *blob = [blobService uploadBlob:imageData
                                     forDid:userDid
                                   mimeType:@"image/jpeg"
                                      error:&error];

// 3. Use CID in record
if (blob) {
    NSDictionary *post = @{
        @"text": @"Check out this image!",
        @"embed": @{
            @"$type": @"app.bsky.embed.image",
            @"image": @{
                @"cid": blob[@"cid"],
                @"mimeType": @"image/jpeg",
                @"size": blob[@"size"]
            }
        }
    };
    
    [recordService putRecord:@"app.bsky.feed.post"
                       rkey:@"abc123"
                      value:post
                     forDid:userDid
                   actorDid:userDid
             validationMode:PDSValidationModeOptimistic
                      error:&error];
}
```

### Downloading a Blob

```objc
// 1. Get blob metadata
NSError *error = nil;
NSDictionary *metadata = [blobService getBlobWithCID:cidString
                                                 did:userDid
                                              error:&error];

// 2. Check if streaming available
NSDictionary *stream = [blobService getBlobStreamWithCID:cidString
                                                     did:userDid
                                                   error:&error];

if (stream) {
    // Stream from file
    NSString *filePath = stream[@"path"];
    [self streamFileFromPath:filePath];
} else {
    // Load into memory
    NSData *blobData = [blobService getBlob:cidData
                                    forDid:userDid
                                     error:&error];
    [self processBlobData:blobData];
}
```

### Listing and Cleaning Up Blobs

```objc
NSMutableArray *allBlobs = [NSMutableArray array];
NSString *cursor = nil;

while (YES) {
    NSError *error = nil;
    NSArray *blobs = [blobService listBlobsForDID:userDid
                                            limit:100
                                           cursor:cursor
                                            error:&error];
    
    if (!blobs) break;
    
    [allBlobs addObjectsFromArray:blobs];
    
    if (blobs.count < 100) break;
    cursor = blobs.lastObject[@"cursor"];
}

// Delete old blobs
for (NSDictionary *blob in allBlobs) {
    NSDate *createdAt = blob[@"createdAt"];
    if ([createdAt timeIntervalSinceNow] < -30*24*3600) { // 30 days old
        [blobService deleteBlobWithCID:blob[@"cid"]
                                  did:userDid
                                 error:&error];
    }
}
```

## See Also

- [Repository Service](./repository-service) - Repository-level operations
- [Services Overview](./services-overview) - How Blob Service fits into the service layer
- [Blob Storage](../07-repository-protocol/blob-storage) - Storage backend implementation
- [Blob Lifecycle](../07-repository-protocol/blob-lifecycle) - Understanding blob lifecycle management
- [Blob Quotas](../07-repository-protocol/blob-quotas) - Implementing storage quotas
- [CID and Hashing](../07-repository-protocol/cid-and-hashing) - Content addressing fundamentals

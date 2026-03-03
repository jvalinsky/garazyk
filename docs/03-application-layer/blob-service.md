# Blob Service

## Overview

The `PDSBlobService` manages binary blob storage and retrieval for ATProto repositories. It handles blob uploads, downloads, metadata management, and deletion with content-addressed storage using CIDs.

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

## Best Practices

1. **Upload Validation**
   - Validate MIME type
   - Check blob size limits
   - Verify DID ownership
   - Rate limit uploads per user

2. **Storage Management**
   - Use file-backed storage for large blobs
   - Implement garbage collection for orphaned blobs
   - Monitor storage usage
   - Set size quotas per user

3. **Performance**
   - Use streaming for large downloads
   - Cache frequently accessed blobs
   - Implement CDN for blob distribution
   - Use compression where appropriate

4. **Security**
   - Validate blob content (magic bytes)
   - Scan for malware
   - Implement access controls
   - Log blob operations

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

- [Repository Service](./repository-service)
- [Services Overview](./services-overview)
- [Blob Storage](../07-repository-protocol/blob-storage)

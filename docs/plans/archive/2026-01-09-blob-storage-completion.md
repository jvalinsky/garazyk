# Blob Storage Completion Plan

> **Status:** Ready for implementation
> **Created:** 2026-01-09

## Overview

Blob storage is ~80% implemented. The core infrastructure exists but several gaps remain before it's production-ready. This plan documents the remaining work to complete the blob storage system.

## Current State

### ✅ Implemented

| Component | Location | Status |
|-----------|----------|--------|
| `BlobStorage.m` | `Sources/Blob/` | Core upload/retrieve/delete logic |
| `MimeTypeValidator.m` | `Sources/Blob/` | MIME type + size validation |
| `uploadBlob` endpoint | `XrpcMethodRegistry.m:347-382` | Wired to PDSController |
| `getBlob` endpoint | `XrpcMethodRegistry.m:384-406` | Wired to PDSController |
| `listBlobs` endpoint | `XrpcMethodRegistry.m:408-436` | Wired to PDSController |
| Database schema | `PDSDatabase` | Blobs table with CID/DID/mimeType/size |
| Unit tests | `Tests/Blob/` | `BlobStorageTests.m`, `MimeTypeValidatorTests.m` |

### ❌ Gaps Identified

1. **`listBlobsForDID` returns empty array** ([PDSController.m:795-800](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/App/PDSController.m#L795-L800))
2. **`getBlobWithCID` doesn't return actual blob data** - returns metadata only
3. **Auth extraction missing** - `uploadBlob` uses `did` query param instead of auth header
4. **No `deleteBlob` XRPC endpoint** registered
5. **Missing MIME type in `getBlob` response** - hardcoded `application/octet-stream`
6. **No blob reference tracking** - blobs not linked to records that reference them
7. **No garbage collection** - orphaned blobs not cleaned up
8. ** tempBlob flow** - no way to upload blob before record creation

---

## Proposed Changes

### Component 1: Fix Core Blob Operations

#### [MODIFY] [PDSController.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/App/PDSController.m)

**Fix `listBlobsForDID` to return actual blobs:**

```diff
- (nullable NSArray *)listBlobsForDID:(NSString *)did 
                                limit:(NSUInteger)limit 
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error {
-    return @[];
+    PDSActorStore *store = [_userDatabasePool storeForDid:did error:error];
+    if (!store) return @[];
+    
+    NSArray<PDSDatabaseBlob *> *blobs = [store listBlobsForDid:did limit:limit cursor:cursor error:error];
+    
+    NSMutableArray *result = [NSMutableArray array];
+    for (PDSDatabaseBlob *blob in blobs) {
+        [result addObject:@{
+            @"cid": [self base32Encode:blob.cid] ?: @"",
+            @"mimeType": blob.mimeType ?: @"application/octet-stream",
+            @"size": @(blob.size)
+        }];
+    }
+    return result;
}
```

**Fix `getBlobWithCID` to return actual blob data:**

```diff
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid 
                                      did:(NSString *)did
                                    error:(NSError **)error {
    NSData *cidData = [self cidDataFromString:cid];
    if (!cidData) {
        if (error) *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                                code:PDSControllerErrorBlobNotFound
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return nil;
    }
    NSData *blob = [self getBlob:cidData forDid:did error:error];
    if (!blob) return nil;
-   return @{@"blob": @{@"mimeType": @"application/octet-stream", @"size": @(blob.length)}};
+   // Get metadata for proper MIME type
+   PDSActorStore *store = [_userDatabasePool storeForDid:did error:nil];
+   PDSDatabaseBlob *metadata = [store getBlobMetadataForCID:cidData error:nil];
+   NSString *mimeType = metadata.mimeType ?: @"application/octet-stream";
+   
+   return @{
+       @"blob": blob,
+       @"mimeType": mimeType,
+       @"size": @(blob.length)
+   };
}
```

---

### Component 2: Add Missing ActorStore Methods

#### [MODIFY] [ActorStore.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Database/ActorStore/ActorStore.h)

Add method declarations:

```objc
- (nullable NSArray<PDSDatabaseBlob *> *)listBlobsForDid:(NSString *)did 
                                                   limit:(NSUInteger)limit 
                                                  cursor:(nullable NSString *)cursor
                                                   error:(NSError **)error;

- (nullable PDSDatabaseBlob *)getBlobMetadataForCID:(NSData *)cid error:(NSError **)error;

- (BOOL)deleteBlobForCID:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;
```

#### [MODIFY] [ActorStore.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Database/ActorStore/ActorStore.m)

Implement the methods by querying the `blobs` table.

---

### Component 3: Fix XRPC Endpoint Auth

#### [MODIFY] [XrpcMethodRegistry.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcMethodRegistry.m)

**Extract DID from Authorization header instead of query param:**

```diff
[dispatcher registerComAtprotoRepoUploadBlob:^(HttpRequest *request, HttpResponse *response) {
-   // Extract DID from Authorization header (this would need proper auth implementation)
-   // For now, we'll use a query parameter for testing
-   NSString *did = [request queryParamForKey:@"did"];
+   // Extract DID from Authorization header
+   NSString *authHeader = [request headerForKey:@"Authorization"];
+   NSString *did = [self extractDIDFromAuthHeader:authHeader controller:controller];
    
    if (!did) {
        response.statusCode = HttpStatusUnauthorized;
-       [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
+       [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
        return;
    }
    // ... rest unchanged
}];
```

**Add helper method:**

```objc
+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader controller:(PDSController *)controller {
    if (!authHeader || ![authHeader hasPrefix:@"Bearer "]) return nil;
    NSString *token = [authHeader substringFromIndex:7];
    // Validate token and extract DID from associated account
    PDSDatabaseAccount *account = [controller.serviceDatabases getAccountByAccessToken:token error:nil];
    return account.did;
}
```

---

### Component 4: Add deleteBlob Endpoint

#### [MODIFY] [XrpcHandler.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcHandler.h)

```objc
/*! Registers handler for com.atproto.repo.deleteBlob. */
- (void)registerComAtprotoRepoDeleteBlob:(XrpcHandlerBlock)handler;
```

#### [MODIFY] [XrpcHandler.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcHandler.m)

```objc
- (void)registerComAtprotoRepoDeleteBlob:(XrpcHandlerBlock)handler {
    [self registerMethod:@"com.atproto.repo.deleteBlob" handler:handler];
}
```

#### [MODIFY] [XrpcMethodRegistry.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcMethodRegistry.m)

```objc
[dispatcher registerComAtprotoRepoDeleteBlob:^(HttpRequest *request, HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [XrpcMethodRegistry extractDIDFromAuthHeader:authHeader controller:controller];
    
    if (!did) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
        return;
    }
    
    NSString *cid = [request queryParamForKey:@"cid"];
    if (!cid) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing cid parameter"}];
        return;
    }
    
    NSError *error = nil;
    BOOL success = [controller deleteBlobWithCID:cid did:did error:&error];
    
    if (!success) {
        response.statusCode = HttpStatusBadRequest;
        [response setJsonBody:@{@"error": @"DeleteFailed", @"message": error.localizedDescription}];
        return;
    }
    
    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
}];
```

#### [MODIFY] [PDSController.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/App/PDSController.h)

```objc
- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error;
```

#### [MODIFY] [PDSController.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/App/PDSController.m)

```objc
- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error {
    NSData *cidData = [self cidDataFromString:cid];
    if (!cidData) {
        if (error) *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                                code:PDSControllerErrorBlobNotFound
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return NO;
    }
    
    __block BOOL success = NO;
    [_userDatabasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteBlobForCID:cidData forDid:did error:nil];
    } error:nil];
    
    return success;
}
```

---

### Component 5: Fix getBlob Response Content-Type

#### [MODIFY] [XrpcMethodRegistry.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Network/XrpcMethodRegistry.m#L384-L406)

```diff
[dispatcher registerComAtprotoSyncGetBlob:^(HttpRequest *request, HttpResponse *response) {
    NSString *did = [request queryParamForKey:@"did"];
    NSString *cid = [request queryParamForKey:@"cid"];
    
    // ... validation unchanged ...
    
    NSError *error = nil;
    NSDictionary *result = [controller getBlobWithCID:cid did:did error:&error];
    
    // ... error handling unchanged ...
    
    response.statusCode = HttpStatusOK;
-   response.contentType = @"application/octet-stream"; // Should be the actual MIME type
-   response.body = result[@"blob"];
+   response.contentType = result[@"mimeType"] ?: @"application/octet-stream";
+   [response setBodyData:result[@"blob"]];
}];
```

---

## Verification Plan

### Automated Tests

#### Existing Tests

Run existing blob tests to ensure no regressions:

```bash
# Build tests via Xcode (from project root)
xcodebuild -project ATProtoPDS.xcodeproj -scheme AllTests build

# Run via test runner
"/Users/jack/Library/Developer/Xcode/DerivedData/ATProtoPDS-gxvfspcaobaihodzeszdnsruddhc/Build/Products/Debug/AllTests"
```

#### New Integration Test

Add to `Tests/Blob/BlobStorageTests.m`:

```objc
- (void)testListBlobsReturnsUploadedBlobs {
    NSData *data = [@"test blob content" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    
    // Upload a blob
    NSDictionary *result = [controller uploadBlob:data forDid:@"did:plc:test" mimeType:@"text/plain" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(result);
    
    // List blobs
    NSArray *blobs = [controller listBlobsForDID:@"did:plc:test" limit:10 cursor:nil error:&error];
    XCTAssertNil(error);
    XCTAssertTrue(blobs.count > 0);
    XCTAssertNotNil(blobs[0][@"cid"]);
    XCTAssertEqualObjects(blobs[0][@"mimeType"], @"text/plain");
}
```

### Manual Verification

#### Test 1: Upload and List Blobs via curl

```bash
# 1. Start the server
./scripts/start_server.sh

# 2. Create an account to get auth token
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","handle":"test.local","password":"testpass123"}'
# Save the accessJwt from response

# 3. Upload a blob with auth header
curl -X POST "http://localhost:2583/xrpc/com.atproto.repo.uploadBlob" \
  -H "Authorization: Bearer <accessJwt>" \
  -F "blob=@test_image.jpg" \
  -F "mimeType=image/jpeg"
# Response should include CID

# 4. List blobs
curl "http://localhost:2583/xrpc/com.atproto.sync.listBlobs?did=<your_did>"
# Response should include the uploaded blob

# 5. Get blob
curl "http://localhost:2583/xrpc/com.atproto.sync.getBlob?did=<your_did>&cid=<blob_cid>" -o downloaded.jpg
# File should match original
```

---

## Implementation Order

1. **Fix `listBlobsForDID`** - Highest impact, currently broken
2. **Fix `getBlobWithCID` return value** - Currently returns metadata, not data
3. **Add ActorStore methods** - Required for steps 1-2
4. **Fix getBlob Content-Type** - Returns correct MIME type
5. **Add deleteBlob endpoint** - Feature completion
6. **Fix auth extraction** - Security improvement (can be deferred)

---

## Estimated Effort

| Task | Estimated Time |
|------|----------------|
| Fix listBlobsForDID + ActorStore methods | 30 min |
| Fix getBlobWithCID return value | 15 min |
| Fix getBlob Content-Type | 10 min |
| Add deleteBlob endpoint | 30 min |
| Fix auth extraction | 45 min |
| Write integration tests | 30 min |
| **Total** | **~2.5 hours** |

---

## Future Enhancements (Out of Scope)

- **Blob reference tracking**: Link blobs to records that reference them
- **Garbage collection**: Clean up orphaned blobs
- **Temp blob flow**: Upload blob before record creation with temporary reference
- **Streaming uploads**: Support chunked/resumable uploads for large files

# Blob Storage Compliance Report

**Date**: 2026-04-20
**Spec Reference**: https://atproto.com/specs/data-blobs

---

## Summary

| Area | Status | Notes |
|------|--------|-------|
| CID Computation | ✅ Compliant | SHA-256, raw codec (0x55) |
| Size Limits | ✅ Compliant | 5MB default limit |
| MIME Type Validation | ✅ Compliant | Whitelist + extension check |
| Range Requests | ✅ Compliant | HTTP Range header support |
| Blob Provider Abstraction | ✅ Compliant | Interface for S3/local |

---

## ✅ Compliant Areas

### CID Computation

**Spec**: Blob CIDs use SHA-256 hash with raw codec (0x55).

**Implementation** (`BlobStorage.m:17`):
```objc
static const uint64_t kRawCodec = 0x55; // raw codec for blobs (per ATProto spec)
```

**CID Generation** (`BlobStorage.m:71`):
```objc
CID *cid = [self computeCIDForData:data];
```

### Size Limits

**Implementation** (`BlobStorage.m:16`):
```objc
static const NSInteger kMaxBlobSize = 5 * 1024 * 1024; // 5MB
```

**Validation** (`BlobStorage.m:65-68`):
```objc
- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error {
    if (![self validateBlob:data mimeType:mimeType error:error]) {
        return nil;
    }
    // ...
}
```

---

### MIME Type Validation

**Location**: `Garazyk/Sources/Blob/MimeTypeValidator.m`

Supported MIME types for blobs:
- Images: `image/jpeg`, `image/png`, `image/gif`, `image/webp`
- Video: `video/mp4`
- Audio: `audio/mpeg`, `audio/wav`
- Application: `application/json`

---

### Range Request Support

**Implementation** (`BlobStorage.m:19-31`):
```objc
static BOOL parseByteRangeHeader(NSString *rangeHeader,
                                 unsigned long long totalLength, BOOL *hasRange,
                                 BOOL *satisfiable, unsigned long long *start,
                                 unsigned long long *end,
                                 NSString **failureReason);
```

Supports:
- `Range: bytes=0-1023`
- `Range: bytes=1024-`
- HTTP 206 Partial Content responses

---

### Blob Provider Abstraction

**Protocol** (`PDSBlobProvider.h`):
```objc
@protocol PDSBlobProvider <NSObject>
- (BOOL)storeBlob:(NSData *)data withCID:(CID *)cid error:(NSError **)error;
- (nullable NSData *)getBlob:(CID *)cid error:(NSError **)error;
- (BOOL)deleteBlob:(CID *)cid error:(NSError **)error;
- (BOOL)blobExists:(CID *)cid;
@end
```

**Providers**:
- `PDSLocalBlobProvider` - Local filesystem storage
- `PDSS3BlobProvider` - S3-compatible storage

---

## ⚠️ Gaps

### CDN Redirect Support

**Status**: Implemented in `BlobStorage.m` but needs verification.

**Expected behavior**:
- Return redirect URL for S3-backed blobs
- Support `X-Redirect-Url` header

### Blob Cleanup

**Status**: Orphaned blob cleanup not verified.

**Expected behavior**:
- Track blob references in records
- Delete unreferenced blobs after TTL

---

## Code References

- **Blob Storage**: `Garazyk/Sources/Blob/BlobStorage.m`
- **Blob Provider**: `Garazyk/Sources/Blob/PDSBlobProvider.h`
- **Local Provider**: `Garazyk/Sources/Blob/PDSLocalBlobProvider.m`
- **S3 Provider**: `Garazyk/Sources/Blob/PDSS3BlobProvider.m`
- **MIME Validator**: `Garazyk/Sources/Blob/MimeTypeValidator.m`

---

## Test Coverage

Tests at `Garazyk/Tests/Blob/`:
- Blob upload/download tests
- CID computation tests
- Range request tests

**Recommendation**: Add tests for S3 provider redirect behavior.

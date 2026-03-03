# Blob Storage Tests

Tests for blob upload, MIME type validation, and XRPC blob endpoints.

## Test Classes

### BlobStorageTests
**File:** `Tests/Blob/BlobStorageTests.m`
**Purpose:** Blob storage layer with disk provider and validation.

| Method | Description |
|--------|-------------|
| `testBlobStorageInitialization` | Storage initializes with pool and provider |
| `testDataSetup` | Test data creation |
| `testBlobValidationValidImage` | Valid image passes validation |
| `testBlobValidationInvalidMimeType` | Invalid MIME type rejected |

---

### BlobXrpcTests
**File:** `Tests/Blob/BlobXrpcTests.m`
**Purpose:** XRPC blob upload endpoint testing.

| Method | Description |
|--------|-------------|
| `testUploadBlobEndpointSuccess` | Upload returns CID reference |

---

### MimeTypeValidatorTests
**File:** `Tests/Blob/MimeTypeValidatorTests.m`
**Purpose:** MIME type format and support validation.

| Method | Description |
|--------|-------------|
| `testValidJPEG` | image/jpeg is valid |
| `testValidPNG` | image/png is valid |
| `testValidWithSubtype` | application/pdf is valid |
| `testInvalidNoSlash` | Missing slash rejected |
| `testInvalidEmptyType` | Empty type rejected |
| `testInvalidEmptySubtype` | Empty subtype rejected |
| `testInvalidNil` | nil rejected |
| `testInvalidEmpty` | Empty string rejected |
| `testCaseNormalization` | Uppercase normalized |
| `testWhitespaceTrimming` | Whitespace trimmed |
| `testSupportedImageJPEG` | JPEG is supported |
| `testSupportedImagePNG` | PNG is supported |
| `testSupportedVideoMP4` | MP4 is supported |
| `testSupportedAudioMPEG` | MPEG audio supported |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/BlobStorageTests
./build/tests/AllTests -only-testing:AllTests/BlobXrpcTests
./build/tests/AllTests -only-testing:AllTests/MimeTypeValidatorTests
```

## Supported MIME Types

| Category | Types |
|----------|-------|
| Image | image/jpeg, image/png, image/gif, image/webp |
| Video | video/mp4, video/webm |
| Audio | audio/mpeg, audio/wav, audio/ogg |

## Related Documentation

- [Folder README](README) - Application tests overview
- [Test Index](../README) - Main test documentation index
- [Services Tests](services) - PDSBlobService tests
- [Database Tests](../03-database/actor-store) - Blob storage in actor store
- [XRPC Tests](../02-network/xrpc) - XRPC blob endpoints
- [Validation Tests](../05-security/validation) - MIME type validation

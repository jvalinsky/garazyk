# Database Layer Review Notes — Blob Storage and MIME Validation

## Scope covered in this pass
- `Garazyk/Sources/Blob/BlobStorage.m`
- `Garazyk/Sources/Blob/MimeTypeValidator.m`
- `Garazyk/Sources/Blob/PDSBlobProviderFactory.m`
- `Garazyk/Sources/Blob/PDSCloudStorageBlobProvider.m`
- `Garazyk/Sources/Blob/PDSDiskBlobProvider.m`
- `Garazyk/Sources/Blob/BlobStorage.h`
- `Garazyk/Sources/Blob/MimeTypeValidator.h`

## Findings

### 1) Disk-backed blob retrieval cannot handle the blob sizes the validator allows
**Severity: high**

`PDSDiskBlobProvider` caps `retrieveBlobDataForCID:` at 5 MB before loading the file into memory, but the MIME validator allows much larger payloads: up to 50 MB for video and 100 MB for model files. `BlobStorage.getBlobWithCID:` calls the provider’s in-memory retrieval path directly, so any blob above 5 MB becomes unreadable even though upload/validation succeeded.

**Why this matters**
- Large blobs can be stored successfully and then fail on every read.
- The API surface already exposes `blobFileURLForCID:` and streaming response support, so this looks like an implementation mismatch rather than an intentional product limit.
- The behavior is especially surprising because the limit is lower than the advertised validation limits.

**Evidence**
- `PDSDiskBlobProvider.m:67-88` enforces the 5 MB retrieval cap.
- `MimeTypeValidator.h:70-73` and `MimeTypeValidator.m:5-12` allow much larger blobs by category.
- `BlobStorage.m:162-190` retrieves through the provider’s memory-backed API.

---

### 2) Magic-number validation is skipped for blobs smaller than 12 bytes
**Severity: medium-high**

`BlobStorage` only calls `validateMagicNumbers:` when `data.length >= 12`, and `MimeTypeValidator.sniffMimeTypeFromData:` immediately returns `nil` for shorter payloads. That means very small files bypass content-type sniffing entirely, including image/video/audio uploads that are exactly the kinds of blobs where spoofing matters most.

**Why this matters**
- A malicious upload can claim a supported MIME type while avoiding signature checks simply by staying under 12 bytes.
- The validator is meant to prevent type spoofing, so this bypass weakens a core safety check.
- Several formats have useful magic numbers well below 12 bytes, so the threshold is arbitrary and too conservative.

**Evidence**
- `BlobStorage.m:328-340` gates magic-number validation on `data.length >= 12`.
- `MimeTypeValidator.m:547-599` refuses to sniff payloads shorter than 12 bytes.

**Suggested direction**
- Remove the hard-coded size gate and let the sniffer validate whatever bytes are available.
- If a format cannot be identified from the available prefix, fail closed for blob categories that require signature validation.

---

### 3) Upload deduplication trusts stale metadata and can preserve missing provider data
**Severity: medium**

`BlobStorage.uploadBlob:` returns early as soon as it finds a metadata row for the CID in the actor store. It does not verify that the provider still has the corresponding blob bytes. If provider data was lost externally or a previous partial failure left metadata behind, re-uploading the same blob will succeed without repairing the missing object.

**Why this matters**
- The metadata row becomes a false positive for blob availability.
- Subsequent reads will still fail because the provider data was never restored.
- This makes recovery from partial failures harder and can leave blobs permanently unreadable.

**Evidence**
- `BlobStorage.m:83-97` returns immediately when `existingBlob` is present.
- The provider existence check only happens after that early return.

**Suggested direction**
- Verify provider presence before treating existing metadata as a complete hit.
- If metadata exists but the provider is missing the object, either restore it or surface a hard inconsistency error.

---

## Notes
- The S3 provider implementation is generally consistent with its synchronous API shape, and the migration / pooling code reviewed earlier looks much stronger than the blob path.
- The biggest correctness gap in this pass is the mismatch between the validator’s allowed blob sizes and the disk provider’s in-memory read cap.

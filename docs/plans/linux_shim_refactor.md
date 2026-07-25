# Linux Platform Shims Refactor Plan

## Objective

Correct four high-impact defects in the Linux compatibility shims:

1. A potential out-of-bounds write in the `CCCrypt` compatibility layer.
2. A cryptographically unsafe entropy fallback.
3. Non-async-signal-safe behavior in the crash reporter.
4. Lossy and incomplete Keychain attribute serialization.

Security-critical changes must land before the broader stability and compatibility fixes.

---

## Phase 1: Security-Critical Fixes

### ✓ 1. Prevent `CCCrypt` Output Buffer Overflows

**File**

`Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonCryptor.c`

**Problem**

The OpenSSL-backed `CCCrypt` implementation may call `EVP_EncryptUpdate`, `EVP_DecryptUpdate`, or the corresponding finalization function before proving that `dataOut` has enough capacity.

OpenSSL writes directly into the caller-provided output buffer. Checking `dataOutAvailable` only after an EVP operation is therefore too late and may permit heap or stack corruption.

**Required changes**

* Determine the selected cipher and obtain its block size before processing input.
* Compute a conservative upper bound for the complete operation, including output produced by both the update and finalization steps.
* Account for:

  * Encryption versus decryption.
  * Block ciphers versus stream-like ciphers.
  * PKCS#7 padding.
  * No-padding mode.
  * Zero-length input.
* Detect integer overflow while calculating the required capacity.
* Validate `dataOutAvailable` before invoking any OpenSSL function that can write to `dataOut`.
* When the supplied buffer is too small:

  * Set `*dataOutMoved` to the required or documented output size when the API contract permits it.
  * Return `kCCBufferTooSmall`.
  * Do not partially encrypt or decrypt the input.
  * Do not write to `dataOut`.
* Preserve existing CommonCrypto-compatible behavior for invalid key sizes, invalid IVs, alignment failures, unsupported algorithms, and OpenSSL errors.
* Ensure every allocated `EVP_CIPHER_CTX` is released on every exit path.

**Sizing guidance**

For padded block-cipher encryption, reserve at least:

```text
dataInLength + blockSize
```

For unpadded block-cipher operations, the input must satisfy the cipher’s alignment requirements and the output should not exceed the input length.

Decryption sizing must still allow for all bytes emitted by `EVP_DecryptUpdate`; padding removal occurs during finalization and must not be treated as a reason to provide a smaller destination buffer.

Use checked arithmetic rather than relying on unchecked expressions such as `dataInLength + blockSize`.

**Acceptance criteria**

* No EVP write operation occurs before output capacity has been validated.
* An undersized output buffer returns `kCCBufferTooSmall`.
* Canary bytes surrounding an undersized test buffer remain unchanged.
* Valid encryption and decryption operations continue to produce the expected results.
* AddressSanitizer reports no out-of-bounds access in the new buffer-sizing tests.

---

### ✓ 2. Remove the Predictable `arc4random` Fallback

**File**

`Garazyk/Sources/Compat/PlatformShims/Security/SecRandom.m`

**Problem**

When both `getrandom(2)` and `/dev/urandom` fail, the current implementation fills the destination buffer with zeros and returns normally.

This converts an entropy-source failure into apparently successful generation of predictable output. Any key, nonce, token, identifier, or credential derived from that output is cryptographically compromised.

**Required changes**

* Remove the zero-filling fallback.
* Attempt entropy acquisition in this order:

  1. `getrandom(2)`, retrying when interrupted by `EINTR`.
  2. `/dev/urandom`, with robust handling of partial reads and interrupted system calls.
* Continue reading until the entire requested buffer has been filled.
* Treat premature EOF, unrecoverable read errors, invalid file descriptors, and complete entropy-source failure as fatal.
* On unrecoverable failure:

  * Emit a minimal diagnostic to `stderr`.
  * Avoid including secret buffer contents in the diagnostic.
  * Terminate immediately with `abort()`.
* Ensure `/dev/urandom` file descriptors are closed on all relevant paths.
* Do not return partially initialized output.

**Implementation note**

The shim implements an API whose callers expect random-byte generation to succeed rather than return an error. Silently degrading the quality of the output is therefore not acceptable. A fail-closed termination is safer than returning predictable data.

**Acceptance criteria**

* No execution path substitutes zero-filled or deterministic data for random bytes.
* `EINTR` and partial-read paths are handled correctly.
* The function either fills the entire buffer with entropy or terminates.
* Repeated normal calls produce non-identical output.
* Failure-injection tests confirm that total entropy-source failure reaches the fatal path.

---

## Phase 2: Stability and Correctness Fixes

### ✓ 3. Make the Crash Signal Handler Async-Signal-Safe

**File**

`Garazyk/Sources/Compat/PlatformShims/CrashReporting/GZCrashReporter.m`

**Problem**

The crash signal handler calls `backtrace_symbols()`. That function allocates memory and may acquire allocator or loader locks.

If the process crashes while the heap or one of those locks is already corrupted, the handler may deadlock, recurse into another fault, or terminate without writing a useful report.

**Required changes**

* Remove `backtrace_symbols()` and any corresponding heap cleanup from the signal-handler path.
* Capture addresses with `backtrace()` only if the supported Linux runtime treats it as acceptable for this best-effort crash path.
* Emit captured frames using `backtrace_symbols_fd()` directly to the already-open crash-log file descriptor.
* Restrict the handler to a minimal set of operations:

  * Fixed-size stack storage.
  * Direct file-descriptor writes.
  * Simple integer or fixed-string output.
  * Signal restoration and process termination.
* Do not use:

  * Objective-C messaging.
  * Foundation APIs.
  * `malloc`, `free`, or functions that may allocate.
  * Buffered `stdio`.
  * Locks or synchronization primitives.
* Open or prepare the crash-log destination before installing the signal handler whenever practical.
* Preserve the original signal disposition or re-raise the signal after the report is written so the process retains expected crash semantics.
* Add a recursion guard using signal-safe state so a second fault in the handler exits immediately rather than repeatedly invoking the reporting path.

**Limitations**

`backtrace()` and symbolization behavior can vary across libc and unwinder implementations. The crash reporter should be treated as best-effort. The primary requirement is that the handler avoid known heap allocation and complex runtime behavior.

**Acceptance criteria**

* The signal-handler path no longer calls `backtrace_symbols()`.
* No explicit heap allocation or Objective-C/Foundation operation occurs in the handler.
* A controlled crash produces a report containing raw or symbolized stack frames.
* A crash caused while allocator state is compromised does not hang indefinitely.
* A recursive signal terminates promptly.

---

### ✓ 4. Replace JSON Keychain Serialization with Property Lists

**File**

`Garazyk/Sources/Compat/PlatformShims/Security/SecItemLinuxStore.m`

**Problem**

`SecItemLinuxStore` serializes Keychain records with `NSJSONSerialization`.

Keychain dictionaries commonly contain values such as:

* `NSData` or `CFData`
* `NSDate` or `CFDate`
* Numbers and booleans
* Strings
* Arrays and dictionaries composed of those types

JSON does not natively preserve raw data or date values. Serialization may fail outright, require lossy conversion, or change the types returned to callers.

**Required changes**

* Replace `NSJSONSerialization` with `NSPropertyListSerialization`.
* Prefer the binary property-list format for compactness and type fidelity unless human-readable storage is an explicit requirement.
* Update all affected read and write paths, including:

  * `addItemWithService`
  * `itemWithService`
  * `updateItemWithService`
  * Any shared serialization helpers used by those methods
* Preserve supported Foundation/CoreFoundation value types without converting dates or binary data to strings.
* Validate that the complete object graph is property-list compatible before writing.
* Propagate serialization and deserialization failures through the existing Keychain-compatible error mechanism.
* Reject malformed or unexpected root objects rather than force-casting them.
* Write updated records atomically:

  1. Serialize into memory.
  2. Write to a temporary file in the same directory.
  3. Apply the intended permissions.
  4. Replace the destination with an atomic rename.
* Preserve restrictive file permissions and avoid broadening access to stored credentials.
* Define migration behavior for existing JSON-backed stores:

  * Attempt property-list decoding first.
  * If that fails, optionally attempt legacy JSON decoding.
  * Rewrite successfully decoded legacy records in property-list format during the next mutation or through an explicit migration step.
* Do not silently delete or overwrite an existing store solely because decoding failed.

**Acceptance criteria**

* Records containing `NSData` and `NSDate` round-trip without loss or type conversion.
* Existing string- and number-only records continue to work.
* Malformed storage returns a controlled error rather than crashing.
* Interrupted writes cannot leave a partially written primary store.
* File permissions remain appropriately restrictive.
* The migration strategy, if retained, successfully reads representative legacy JSON records.

---

## Phase 3: Validation and Regression Coverage

### Automated tests

Run the complete compatibility test suite:

```text
Garazyk/Tests/Compat/
```

Add focused regression tests for each defect.

#### `CCCrypt`

* Encrypt and decrypt with correctly sized buffers.
* Pass an output buffer that is one byte too small.
* Test zero-length input.
* Test padded and unpadded operations.
* Test input lengths at, below, and above block boundaries.
* Verify `dataOutMoved` behavior on success and failure.
* Surround the output buffer with canary bytes and confirm they are unchanged after a rejected operation.
* Run under AddressSanitizer and UndefinedBehaviorSanitizer.

#### Randomness shim

* Exercise successful `getrandom` operation.
* Simulate `EINTR`.
* Simulate partial reads.
* Exercise the `/dev/urandom` fallback.
* Inject total entropy-source failure in a subprocess and verify abnormal termination.
* Confirm that no failure path returns a zero-filled buffer.

#### Crash reporter

* Trigger a controlled fatal signal in a subprocess.
* Confirm that a crash report is written.
* Confirm that the report contains stack-frame output.
* Add a timeout so a deadlocked handler fails the test.
* Trigger a second signal while handling the first and verify prompt termination.
* Inspect the handler implementation for accidental Foundation, Objective-C, allocation, locking, or buffered-I/O calls.

#### Keychain store

* Round-trip values containing strings, numbers, booleans, dates, binary data, arrays, and nested dictionaries.
* Add, retrieve, update, and delete representative records.
* Verify behavior for malformed or truncated files.
* Verify atomic replacement behavior.
* Verify on-disk permissions.
* Test legacy JSON migration if backward compatibility is implemented.

### Manual validation

* Run the relevant application flows that consume the Linux shims.
* Confirm that existing encrypted data remains readable where compatibility is expected.
* Confirm that Keychain-backed authentication data survives an application restart.
* Confirm that a deliberately induced crash produces a useful log and terminates normally for a crashed process.
* Confirm that no plaintext secrets, keys, or random-buffer contents appear in diagnostics.

---

## Phase 4: Final Review

Before merging:

* Review all changed error paths for resource leaks and partially initialized output.
* Verify that security-sensitive failures are fail-closed.
* Confirm that public shim behavior remains compatible with the Apple APIs being emulated.
* Run the full test suite with sanitizers enabled.
* Document any intentional behavioral differences from Apple platforms.
* Keep the four fixes in separate commits where practical so each change can be reviewed and reverted independently.

## Recommended Implementation Order

1. Fix and test `CCCrypt` output sizing.
2. Remove the random-byte zero fallback.
3. Refactor the crash signal handler.
4. Replace Keychain JSON serialization and implement migration.
5. Run sanitizer, compatibility, integration, and failure-injection tests.

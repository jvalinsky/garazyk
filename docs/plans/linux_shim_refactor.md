# Linux Platform Shims Refactor Plan

## Objective

Fix four defects in the Linux compatibility shims:

1. Out-of-bounds write in the `CCCrypt` compatibility layer.
2. Unsafe entropy fallback.
3. Non-async-signal-safe crash reporter.
4. Lossy Keychain attribute serialization.

Fix security defects before stability issues.

## Phase 1: Security Fixes

### ✓ 1. Fix `CCCrypt` Buffer Overflows

**File**
`Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonCryptor.c`

**Problem**
The `CCCrypt` implementation calls OpenSSL update or finalization functions before verifying `dataOut` capacity. OpenSSL writes directly to the output buffer. Checking `dataOutAvailable` after the operation allows buffer overflows.

**Required changes**
* Get the cipher block size before processing input.
* Calculate the required capacity for both the update and finalization steps.
* Account for encryption vs. decryption, block vs. stream ciphers, PKCS#7 padding, no padding, and zero-length input.
* Check for integer overflow during capacity calculation.
* Validate `dataOutAvailable` before calling any OpenSSL function that writes to `dataOut`.
* If the buffer is too small:
  * Set `*dataOutMoved` to the required size if the API contract permits.
  * Return `kCCBufferTooSmall`.
  * Do not encrypt or decrypt the input.
  * Do not write to `dataOut`.
* Retain CommonCrypto behavior for invalid key sizes, invalid IVs, alignment failures, unsupported algorithms, and OpenSSL errors.
* Release every allocated `EVP_CIPHER_CTX` on all exit paths.

**Sizing guidance**
For padded block-cipher encryption, require `dataInLength + blockSize`. Use checked arithmetic.

For unpadded block-cipher operations, the output length matches the input length.

For decryption, allocate space for all bytes emitted by `EVP_DecryptUpdate`. Do not reduce the required capacity to account for padding removal during finalization.

**Acceptance criteria**
* The capacity check runs before OpenSSL writes to the buffer.
* An undersized buffer returns `kCCBufferTooSmall`.
* Canary bytes surrounding an undersized test buffer remain unchanged.
* Valid operations produce expected results.
* AddressSanitizer detects no out-of-bounds access.

### ✓ 2. Remove `arc4random` Fallback

**File**
`Garazyk/Sources/Compat/PlatformShims/Security/SecRandom.m`

**Problem**
If `getrandom(2)` and `/dev/urandom` fail, the implementation zero-fills the buffer and returns success. This masks entropy failures and compromises derived keys.

**Required changes**
* Remove the zero-fill fallback.
* Attempt `getrandom(2)`, handling `EINTR`.
* If `getrandom(2)` fails, attempt `/dev/urandom`, handling partial reads and `EINTR`.
* Continue reading until the buffer is full.
* Treat premature EOF, unrecoverable read errors, invalid file descriptors, and total entropy failure as fatal.
* On unrecoverable failure, print a short diagnostic to `stderr` and call `abort()`. Do not log buffer contents.
* Close `/dev/urandom` file descriptors on all paths.

**Implementation note**
Callers expect this API to succeed. Terminate the process if entropy generation fails.

**Acceptance criteria**
* The function never returns zero-filled or predictable data.
* `EINTR` and partial reads succeed.
* The function fills the buffer or aborts.
* Total entropy failure aborts the process.

## Phase 2: Stability Fixes

### ✓ 3. Make Crash Reporter Async-Signal-Safe

**File**
`Garazyk/Sources/Compat/PlatformShims/CrashReporting/GZCrashReporter.m`

**Problem**
The signal handler calls `backtrace_symbols()`, which allocates memory. If the heap or lock state is corrupt, the handler can deadlock, fault again, or exit without writing the report.

**Required changes**
* Remove `backtrace_symbols()`.
* Call `backtrace()` only if the Linux runtime treats it as safe for crash paths.
* Write frames with `backtrace_symbols_fd()` directly to the crash-log file descriptor.
* Restrict the handler to stack storage, direct file-descriptor writes, integer/string formatting, and signal restoration.
* Remove all Objective-C messaging, Foundation APIs, memory allocation, buffered I/O, and locks.
* Open the crash-log file descriptor before installing the signal handler.
* Restore the original signal disposition or re-raise the signal after writing the report.
* Add a recursion guard using signal-safe state to exit immediately on a second fault.

**Acceptance criteria**
* The handler does not call `backtrace_symbols()`.
* The handler performs no heap allocation or Objective-C operations.
* A controlled crash writes a report with stack frames.
* A crash with corrupt allocator state does not deadlock.
* A recursive signal terminates the process.

### ✓ 4. Use Property Lists for Keychain

**File**
`Garazyk/Sources/Compat/PlatformShims/Security/SecItemLinuxStore.m`

**Problem**
`SecItemLinuxStore` uses `NSJSONSerialization`. JSON does not preserve binary data or dates. Serialization loses data or changes types.

**Required changes**
* Use `NSPropertyListSerialization` instead of `NSJSONSerialization`.
* Use the binary format for compactness and type fidelity.
* Update `addItemWithService`, `itemWithService`, `updateItemWithService`, and shared serialization methods.
* Validate the object graph before writing.
* Return errors through the Keychain error mechanism.
* Reject malformed root objects.
* Write records atomically:
  1. Serialize to memory.
  2. Write to a temporary file.
  3. Apply permissions.
  4. Rename the temporary file over the destination.
* Preserve restrictive file permissions.
* For migration:
  * Attempt property-list decoding.
  * If decoding fails, attempt legacy JSON decoding.
  * Write successfully decoded JSON records as property lists during the next mutation.
* Never delete the store due to decoding failures.

**Acceptance criteria**
* `NSData` and `NSDate` values round-trip correctly.
* String and number records function correctly.
* Malformed storage returns an error without crashing.
* Interrupted writes do not corrupt the primary store.
* File permissions restrict access.
* The migration reads legacy JSON records.

## Phase 3: Testing

Run `Garazyk/Tests/Compat/` and add regression tests for each defect.

### `CCCrypt`
* Test correct, undersized (1 byte short), and zero-length buffers.
* Test padded and unpadded operations.
* Test input lengths at, below, and above block boundaries.
* Verify `dataOutMoved`.
* Verify canary bytes remain unchanged around rejected buffers.
* Run with ASan and UBSan.

### SecRandom
* Test `getrandom` success, `EINTR`, and partial reads.
* Test `/dev/urandom` fallback.
* Inject total entropy failure and verify abnormal termination.

### Crash Reporter
* Trigger a fatal signal in a subprocess and verify the report contains stack frames.
* Add a timeout to catch deadlocks.
* Trigger a recursive signal and verify termination.
* Audit the handler for unsafe calls.

### Keychain Store
* Round-trip records with strings, numbers, booleans, dates, binary data, arrays, and dictionaries.
* Test CRUD operations.
* Verify malformed file handling.
* Verify atomic replacement and permissions.
* Test legacy JSON migration.

## Phase 4: Final Review

* Check error paths for resource leaks.
* Verify security failures fail closed.
* Confirm API compatibility with Apple platforms.
* Run tests with sanitizers.
* Separate the four fixes into independent commits.

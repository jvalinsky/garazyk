# CCCrypt Buffer Size Calculation for PKCS7 Padding

When using Apple's `CCCrypt` function from the CommonCrypto library with `kCCOptionPKCS7Padding`, the output buffer size needs to be carefully calculated to avoid buffer overflows or `kCCBufferTooSmall` errors.

## The Flaw in the Linux Shim (`CommonCryptor.c`)
Currently, the shim wraps OpenSSL's `EVP_EncryptUpdate`. The shim writes ciphertext to `dataOut` *before* verifying that `dataOutAvailable` is actually large enough. This is dangerous because OpenSSL assumes the provided buffer has enough space. In the worst-case scenario, this triggers a heap buffer overflow, corrupting application memory before returning an error.

## The Correct Buffer Calculation
To safely pre-allocate or verify an output buffer when encrypting with PKCS7 padding, you must account for the maximum potential padding block.

The formula for the maximum required output buffer size is:
`outputBufferSize = inputDataLength + kCCBlockSizeAlgorithm`

For example, when using AES-128 (or AES-192/256 since the block size is still 16 bytes for all AES variants):
`size_t maxOutputSize = dataInLength + kCCBlockSizeAES128;`

## Rationale
PKCS7 padding always adds between `1` and `block_size` bytes to ensure the output is a strict multiple of the block size. Even if the input size is already aligned to the block size, a full block of padding is appended. Thus, providing `inputDataLength + blockSize` guarantees sufficient space for both the ciphertext and the padding.

## Implementation Fix Strategy
Before calling `EVP_EncryptUpdate`, the shim should statically determine the maximum output size based on `dataInLength`, `kCCBlockSizeAES128`, and whether `kCCOptionPKCS7Padding` is specified. If the user-provided `dataOutAvailable` is smaller than this calculated size, the shim must immediately return `kCCBufferTooSmall` without invoking OpenSSL or touching `dataOut`.

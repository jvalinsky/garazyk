# Cryptographic PRNG Fallback Behavior (`arc4random`)

## The Concept of `arc4random`
The `arc4random(3)` family of functions originated in OpenBSD and is designed to provide high-quality pseudo-random data. Its defining characteristic is that it **cannot fail** from the caller's perspective. It has a `void` return type, so callers are never expected to check for error codes.

## The Flaw in the Linux Shim (`SecRandom.m`)
The Linux shim implements `arc4random_buf` by attempting to use `getrandom(2)`. If that syscall fails or is interrupted too many times, it falls back to reading `/dev/urandom`. 

If opening or reading from `/dev/urandom` also fails (e.g., due to file descriptor exhaustion, chroot missing the device node, or restrictive sandboxes), the shim zeroes out the provided buffer:
```c
int fd = open("/dev/urandom", O_RDONLY);
if (fd < 0) {
    memset(buf, 0, nbytes);
    return;
}
```

This is a **catastrophic security vulnerability**. By silently returning zeroes, any downstream cryptography that relies on `arc4random` (such as key generation, IV initialization, or nonces) will use predictable, static all-zero data. This completely breaks encryption.

## Correct Behavior (The OpenBSD Standard)
Because `arc4random` guarantees success, the only safe and correct action when entropy cannot be gathered is to terminate the process.

OpenBSD's implementation (and compliant ports) will typically call `abort()` if the underlying entropy source (`getentropy(2)`) somehow fails in a fatal way. It is far better for an application to crash immediately than to continue operating with a compromised security state.

## Implementation Fix Strategy
The `memset(buf, 0, nbytes)` fallback must be completely removed. If both `getrandom` and `/dev/urandom` fail to yield sufficient entropy, the shim must log a critical failure to `stderr` and immediately call `abort()`.

---
title: The Objective-C Environment
description: Clang, GNUstep, ARC, and cross-platform server development
---

Garazyk is an Objective-C server built on Foundation and C libraries. The code
calls SQLite, OpenSSL, POSIX networking, and `libdispatch` APIs without a
language bridge. Objective-C classes provide ownership and service boundaries
around those lower-level interfaces.

## Supported toolchains

The macOS build uses Apple's Clang, Foundation, and system frameworks. Linux
builds use Clang, `libobjc2`, GNUstep Base, BlocksRuntime, and `libdispatch`.

Common dependencies include:

- `sqlite3` for service databases and actor repositories
- OpenSSL and libsecp256k1 for protocol cryptography
- `libdispatch` for queues, groups, sources, and semaphores
- GNUstep Base for Foundation APIs on Linux

The two platforms do not expose identical runtime behavior. Compatibility shims
live under `Garazyk/Sources/Compat/`, and platform-specific code should stay
behind a narrow interface.

## Building

Use an out-of-source CMake build:

```sh
cmake -S . -B build
cmake --build build --parallel 4
```

Run `xcodegen generate` before building the macOS Xcode project. Linux and
GNUstep changes should also be checked with the repository's container build
because code that compiles against Apple Foundation may use unavailable
selectors or different API contracts.

## Automatic Reference Counting

Garazyk builds with Automatic Reference Counting (ARC). Clang inserts
Objective-C retain and release operations based on ownership qualifiers and
control flow. ARC does not manage C allocations, SQLite handles, OpenSSL
objects, file descriptors, or other non-Objective-C resources; their owning
types still need explicit cleanup.

ARC also does not prevent reference cycles. A copied block strongly retains
Objective-C objects that it captures unless the capture is weak or unsafe. A
cycle occurs when an object retains a block and that block retains the object.

Use a weak capture only when the ownership graph requires it:

```objc
__weak typeof(self) weakSelf = self;

[self.networkClient fetchRecord:uri completion:^(NSDictionary *record, NSError *error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
        return;
    }

    [strongSelf handleRecord:record error:error];
}];
```

Promoting the weak reference once at the start of the block keeps the object
alive for the rest of that execution. If the object must outlive the operation
by contract, a strong capture may be the correct choice. Document the ownership
rule instead of applying the weak/strong pattern to every asynchronous block.

## C resource ownership

Objective-C wrappers should give each C resource one visible owner:

```objc
EVP_MD_CTX *context = EVP_MD_CTX_new();
if (context == NULL) {
    return NO;
}

@try {
    // Configure and use context.
} @finally {
    EVP_MD_CTX_free(context);
}
```

The same rule applies to `sqlite3_stmt *`, `sqlite3 *`, allocated buffers, and
file descriptors. Garazyk uses cleanup helpers in several subsystems, but
callers must confirm the helper's exact scope before relying on it.

## Nullability and collection types

Public headers use `NS_ASSUME_NONNULL_BEGIN` with explicit `nullable`
annotations for optional values. Add lightweight generics to Foundation
collections so callers and documentation tools can see element types:

```objc
- (nullable NSArray<NSDictionary<NSString *, id> *> *)recordsForDID:(NSString *)did
                                                               error:(NSError **)error;
```

Error-returning methods should describe whether `nil` or `NO` signals failure
and which error pointer receives details.

## Concurrency contracts

ARC makes object lifetime safer; it does not make mutable objects thread-safe.
Each service should state whether it is confined to a queue, accepts calls from
any queue, or protects its state with a lock or atomic primitive. Do not infer
safety from an `atomic` property declaration.

Keep queue assertions close to protected state, avoid synchronous re-entry into
serial queues, and test the contract on both Darwin and GNUstep/Linux.

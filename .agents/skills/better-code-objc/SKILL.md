---
name: better-code-objc
description: "Modern Objective-C implementation standards (2024-2026): ARC invariants, Static Safety, and Concurrency-safe Primitives."
---

# Better Code: Objective-C Excellence

This skill defines the standards for high-quality Objective-C implementation in this repository.

## Memory & State Safety

### 1. ARC Invariants
ARC is mandatory. 
- Use `__weak` self patterns in blocks to prevent retain cycles.
- Use `__strong` capture inside the block to ensure the object stays alive during execution.

### 2. Designated Initializers
Enforce consistent object state using `NS_DESIGNATED_INITIALIZER`.
- Every class must have a clear "entry point" for initialization.
- Subclasses must override the designated initializer of the superclass.

## Static Safety & Hygiene

### 1. Nullability Annotations
Use `_Nullable`, `_Nonnull`, and `_Null_unspecified` everywhere.
- Wrap headers in `NS_ASSUME_NONNULL_BEGIN` / `NS_ASSUME_NONNULL_END`.
- This informs both the compiler and Swift interoperability.

### 2. Lightweight Generics
Avoid type erasure in collections.
- Use `NSArray<Type *> *` instead of raw `NSArray *`.
- This improves IDE autocomplete and prevents runtime type errors.

## Concurrency & Performance

### 1. Boring Synchronization
Prefer simple, predictable synchronization over complex locking.
- Use **Serial Dispatch Queues** as synchronization primitives instead of `@synchronized`.
- Ensure UI updates occur strictly on the main thread via `dispatch_async(dispatch_get_main_queue(), ...)`.

### 2. GCD vs NSOperation
- Use **GCD** for simple, fire-and-forget async tasks.
- Use **NSOperationQueue** for complex workflows requiring dependencies, prioritization, or cancellation.

## Error Handling Pattern

Follow the Cocoa `NSError **` convention strictly:
1. Method returns a `BOOL` (success) or a nullable object.
2. Check the return value **first** (e.g., `if (!result)`).
3. Only then inspect the `NSError` pointer.
4. Fail loudly during development (`NSAssert`) for programmer errors; fail gracefully via `NSError` for runtime errors.

## Modular Boundaries
- Define module interfaces via **Protocols** (Interfaces).
- Use Protocols to facilitate dependency injection and mock-based testing.
- Keep implementation details hidden in the `.m` file or a private category header.

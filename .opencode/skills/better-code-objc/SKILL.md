name: better-code-objc
description: Modern Objective-C implementation standards (2024-2026): ARC invariants, nullability annotations, designated initializers, and GCD-based concurrency. Use when writing, reviewing, or refactoring Objective-C code.

# Better Code: Objective-C

Full implementation standards are defined in `.agents/skills/better-code-objc/SKILL.md`.

## Key Principles
- **ARC mandatory**: `__weak` self in blocks, `__strong` capture inside
- **Nullability**: `_Nonnull`/`_Nullable` everywhere, `NS_ASSUME_NONNULL_BEGIN`
- **Designated initializers**: Clear entry point per class
- **Serial queues**: Preferred over `@synchronized` for synchronization
- **NSError convention**: Return BOOL/object, check return first, then error

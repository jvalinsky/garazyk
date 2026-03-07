---
title: "Appendix: Runtime Mutation, Associated Objects, Swizzling, and Direct Methods"
description: Deep research notes for Objective-C runtime tricks, associated objects, method swizzling, dynamic ivars, and direct methods
outline: deep
---

# Appendix: Runtime Mutation, Associated Objects, Swizzling, and Direct Methods

Use this appendix when a change proposal stops looking like ordinary Objective-C
and starts looking like runtime surgery.

## Associated objects: when they are acceptable and when they are not

NSHipster's associated-objects article is still valuable because it is practical
and skeptical at the same time.

The parts that matter most:

- associated objects are a category-state tool, not a substitute for normal
  object design
- keys must be pointer-unique; selectors are a clean option
- `OBJC_ASSOCIATION_ASSIGN` behaves like `unsafe_unretained`, not zeroing weak
- clearing one association with `objc_setAssociatedObject(..., nil, ...)` is
  safer than blasting everything with `objc_removeAssociatedObjects`
- associated storage is best treated as a last resort

If you cannot explain why subclassing, composition, delegation, notification, or
an explicit side table is worse, an associated object probably is not justified.

## Swizzling is global state, not a local trick

The best historical swizzling guidance still holds:

- swizzle in `+load`
- do it exactly once
- preserve the original implementation unless you have a very strong reason not
  to
- treat the change as process-wide global state

Even when technically correct, swizzling raises debugging cost because callers
cannot see the real control flow from the type signature alone. In September,
that usually makes it the wrong tool.

## Direct methods change the rules

The official Clang docs are the most important source here, with NSHipster as
the readable companion.

`objc_direct` and related features are niche, but they matter because they break
assumptions that runtime-oriented debugging often depends on:

- direct methods do not call through `objc_msgSend`
- they cannot be overridden dynamically like ordinary Objective-C methods
- they are not listed in the class method lists
- they cannot satisfy protocol requirements in the ordinary dynamic way

This means runtime inspection, swizzling, forwarding, and selector-based tricks
may simply not see them.

## Historical techniques worth reading only as history

Two older Cocoa with Love pieces are still worth knowing about, mostly so you do
not cargo-cult them:

- dynamic ivars are conceptually interesting for binary-compatibility and
  runtime-layout history, but the article is explicitly old-era material and the
  technique only applies before class registration
- arbitrary "is this pointer a valid object?" checks are useful as debugger
  thought experiments, not production logic

They are good research, but they are not a green light for repository design.

## September decision rule

If a technique depends on hidden runtime state, invisible category storage,
process-wide method replacement, or dispatch behavior the caller cannot infer,
you need a stronger justification than "Objective-C allows it."

That does not mean the knowledge is useless. It means the primary value here is:

- debugging code you inherited
- auditing risky proposals
- understanding why an opaque behavior is happening

If the goal is new repository code, prefer explicit ownership, explicit
protocols, and visible composition boundaries.

## Research trail

- [Objective-C Runtime](https://developer.apple.com/documentation/objectivec/objective-c-runtime)
  - `current`
  - Use for current runtime API boundaries and supported low-level hooks.
- [Attributes in Clang](https://clang.llvm.org/docs/AttributeReference.html)
  - `current`
  - Primary source for `objc_direct` and `objc_direct_members`.
- [Associated Objects](https://nshipster.com/associated-objects/)
  - `conceptually useful but dated`
  - Strong practical guidance, especially on policies and anti-patterns.
- [Method Swizzling](https://nshipster.com/method-swizzling/)
  - `conceptually useful but dated`
  - Useful mainly as a hazards guide.
- [Objective-C Direct Methods](https://nshipster.com/direct/)
  - `conceptually useful but dated`
  - Good readable explanation of what direct methods opt out of.
- [Dynamic ivars: solving a fragile base class problem](https://www.cocoawithlove.com/2010/03/dynamic-ivars-solving-fragile-base.html)
  - `historical only`
  - Worth reading for runtime-layout history and its limits.
- [Testing if an arbitrary pointer is a valid object pointer](https://www.cocoawithlove.com/2010/10/testing-if-arbitrary-pointer-is-valid.html)
  - `historical only`
  - Debugger-only thinking, not production guidance.
- [5 key-value coding approaches in Cocoa](https://www.cocoawithlove.com/2010/01/5-key-value-coding-approaches-in-cocoa.html)
  - `historical only`
  - Useful for seeing associated objects as one KVC-era technique among several.

## Search recipes

```text
site:nshipster.com "associated objects" Objective-C
site:nshipster.com "method swizzling" Objective-C
site:nshipster.com "direct methods" Objective-C
site:clang.llvm.org objc_direct objc_direct_members Objective-C
site:cocoawithlove.com "dynamic ivars" Objective-C
site:cocoawithlove.com "valid object pointer" Objective-C
site:developer.apple.com "Objective-C runtime" class_addIvar objc_setAssociatedObject
```

---
title: Objective-C Research Map
description: Contributor-facing lookup guide for obscure Objective-C, Cocoa, runtime, and macOS questions in Garazyk PDS
outline: deep
---

# Objective-C Research Map

## Why this exists

When a change involves obscure Objective-C or Cocoa concepts, normal code search is
not enough. The repository has strong tests and explicit architecture, but niche
questions about `KVO`, `NSInvocation`, message forwarding, associated objects,
`autorelease pool` behavior, or `AppKit` benefit from outside research.

This page maps symptoms to research sources. It provides lookup and debugging
help, not beginner Objective-C training.

## Trust order for sources

Use sources in this order unless you have a reason not to:

1. Current Apple docs and headers for supported APIs, availability, and
   semantics.
2. Apple archive docs for older Cocoa conceptual writing that still explains
   contracts better than modern API references.
3. Garazyk code and tests for what the repository actually does today.
4. Mike Ash, Cocoa with Love, objc.io, NSHipster, Cocoa Is My Girlfriend, and
   Chris Eidhof for mental models, edge cases, and niche techniques.
5. Eclectic Light for current macOS behavior, logs, Spotlight, metadata, and
   system quirks that affect Objective-C software on modern macOS.

If an old article and current code disagree, trust current code and current
Apple APIs first.

## If you are debugging or changing X, start here

| If you are touching... | Start with | Then read |
| --- | --- | --- |
| route-handler retain cycles, callback lifetime, weak references, or `autorelease pool` behavior | [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) section on memory and object lifetimes | [Troubleshooting](./troubleshooting), [Testing Map](./testing-map) |
| selector surprises, `message forwarding`, `NSInvocation`, `NSProxy`, or `swizzling` | [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) section on runtime and messaging | [Codebase Map](../01-getting-started/codebase-map), [Objective-C Runtime](https://developer.apple.com/documentation/objectivec/objective-c-runtime) |
| `KVC`, `KVO`, bindings, or category storage via associated objects | [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) section on Cocoa dynamism | [Troubleshooting](./troubleshooting), [Key-Value Coding Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/KeyValueCoding/index.html), [Key-Value Observing Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/KeyValueObserving/KeyValueObserving.html) |
| queue ownership, `NSOperation`, callback ordering, run loops, teardown hangs, or incremental parsing | [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) section on concurrency and orchestration | [Test Selection Workflow](./test-selection-workflow), [Backpressure](../08-sync-firehose/backpressure) |
| predicates, value objects, keyed archiving, Core Data concepts, or model-boundary confusion | [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) section on data and model layers | [Config Reference](./config-reference), nearby service or repository docs |
| `AppKit`, `XPC`, LLDB, logs, Spotlight, metadata, or macOS-specific behavior | [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) section on macOS-specific internals | [macOS & Linux](../09-platform-compatibility/macos-linux), [Deep Dive: macOS vs GNUstep Boundary](../09-platform-compatibility/macos-vs-gnustep-boundary) |
| SQLite finalization, CF ownership, or Objective-C/C resource boundaries | [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) section on memory and object lifetimes | [SQLite Architecture](../05-database-layer/sqlite-architecture), [Data Integrity](../05-database-layer/data-integrity) |

## Evidence tags

Use these tags to gauge an external article's reliability:

- `current`: safe as a first stop for current APIs or observed behavior
- `conceptually useful but dated`: useful for mental models, but re-check API
  details before applying directly
- `historical only`: useful for old Cocoa lore, retired behavior, or debugging
  context, not for direct production guidance

The older the article, the more likely you need to translate it through ARC,
modern 64-bit runtime behavior, and current framework contracts.

## Quick query recipes

Use direct site-scoped searches when broad web search fails:

```text
site:mikeash.com/pyblog/friday-qa "message forwarding" Objective-C
site:mikeash.com/pyblog/friday-qa ARC Objective-C weak blocks
site:cocoawithlove.com NSInvocation Objective-C
site:objc.io/issues/7-foundation "Key-Value"
site:objc.io/issues/2-concurrency NSOperation GCD run loop
site:nshipster.com "associated objects"
site:nshipster.com "method swizzling"
site:cimgf.com KVO KVC Objective-C
site:developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt weak autorelease pool
site:developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaViewsGuide AppKit NSView
site:eclecticlight.co logs Spotlight metadata macOS
```

If you already know the category, jump straight to the deep guide cluster and
reuse its search recipes rather than starting from a blank browser tab.

## Go deeper in Garazyk docs

Use these pages together:

- [Objective-C Research Patterns & Techniques](../guides/objective_c_tips) for
  the full research-driven compendium and annotated source list
- [Objective-C Research Appendices](../guides/objective-c-appendices/) for
  source-backed deep dives on forwarding, lifetime edges, runtime mutation,
  observation boundaries, and macOS investigation
- [Troubleshooting](./troubleshooting) when the problem is already showing up as
  a failing surface
- [Testing Map](./testing-map) and
  [Test Selection Workflow](./test-selection-workflow) when you need the
  smallest useful verification path
- [Codebase Map](../01-getting-started/codebase-map) when you know the concept
  but not the owning subsystem
- [macOS & Linux](../09-platform-compatibility/macos-linux) when the behavior
  might be platform-specific instead of purely Objective-C-specific

## Related

- [Documentation Map](documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


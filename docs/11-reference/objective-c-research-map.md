---
title: Objective-C Research Map
description: Contributor-facing lookup guide for obscure Objective-C, Cocoa, runtime, and macOS questions in Garazyk PDS
outline: deep
---

# Objective-C Research Map

Standard code search often fails when changes involve obscure Objective-C or Cocoa concepts. While this repository maintains strong tests and explicit architecture, niche questions about KVO, `NSInvocation`, message forwarding, associated objects, autorelease pool behavior, or AppKit require external research. This map connects symptoms to research sources.

## Source Trust Hierarchy

1. Apple Documentation and Headers: Verify supported APIs, availability, and semantics.
2. Apple Archive: Read older Cocoa conceptual writing for clear contract explanations.
3. Garazyk Code and Tests: Confirm current repository implementation.
4. Community Experts: Consult Mike Ash, Cocoa with Love, objc.io, NSHipster, Cocoa Is My Girlfriend, and Chris Eidhof for mental models and edge cases.
5. Eclectic Light: Research current macOS behavior, system logs, Spotlight, and metadata quirks.

Trust current code and active Apple APIs if they conflict with older articles.

## Research Entry Points

| Topic | Primary Source | Secondary Source |
| --- | --- | --- |
| Retain cycles, callback lifetime, weak references, or autorelease pools | [Objective-C Research Patterns](../guides/objective_c_tips) (Memory section) | [Troubleshooting](./troubleshooting), [Testing Map](./testing-map) |
| Selector surprises, message forwarding, `NSInvocation`, `NSProxy`, or swizzling | [Objective-C Research Patterns](../guides/objective_c_tips) (Runtime section) | [Codebase Map](../01-getting-started/codebase-map), [Apple Runtime Docs](https://developer.apple.com/documentation/objectivec/objective-c-runtime) |
| KVC, KVO, bindings, or associated objects | [Objective-C Research Patterns](../guides/objective_c_tips) (Dynamism section) | [Troubleshooting](./troubleshooting), [KVC Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/KeyValueCoding/index.html) |
| Queue ownership, `NSOperation`, run loops, or incremental parsing | [Objective-C Research Patterns](../guides/objective_c_tips) (Concurrency section) | [Test Selection](./test-selection-workflow), [Backpressure](../08-sync-firehose/backpressure) |
| Predicates, value objects, keyed archiving, or model boundaries | [Objective-C Research Patterns](../guides/objective_c_tips) (Data section) | [Config Reference](./config-reference), local service docs |
| AppKit, XPC, LLDB, Spotlight, or metadata | [Objective-C Research Patterns](../guides/objective_c_tips) (macOS section) | [macOS & Linux](../09-platform-compatibility/macos-linux) |
| SQLite finalization, CF ownership, or C resource boundaries | [Objective-C Research Patterns](../guides/objective_c_tips) (Memory section) | [SQLite Architecture](../05-database-layer/sqlite-architecture) |

## Reliability Tags

Translate older articles to account for ARC, 64-bit runtime behavior, and current framework contracts.

- `current`: Safe for active APIs and observed behavior.
- `conceptually useful but dated`: Good for mental models; verify API details before implementation.
- `historical`: Useful for debugging context or retired behavior. Do not use for production guidance.

## Search Recipes

Execute site-scoped searches for specific problems:

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

## Related Resources

- [Objective-C Research Patterns](../guides/objective_c_tips): Compendium and annotated source list.
- [Objective-C Research Appendices](../guides/objective-c-appendices/): Dives on forwarding and lifetime.
- [Troubleshooting](./troubleshooting): Guidance for active failures.
- [Testing Map](./testing-map): Verification paths.
- [Codebase Map](../01-getting-started/codebase-map): Subsystem ownership.
- [macOS & Linux](../09-platform-compatibility/macos-linux): Platform behavior.
- [Documentation Map](documentation-map.md)

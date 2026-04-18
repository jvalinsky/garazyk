---
title: Objective-C Research Appendices
description: Source-backed appendix pages for obscure Objective-C, Cocoa runtime, observation, and macOS investigation topics
outline: deep
---

# Objective-C Research Appendices

These pages are the deep-dive companions to
[Objective-C Research Patterns & Techniques](../objective_c_tips) and
[Objective-C Research Map](../../11-reference/objective-c-research-map).

Use them when the main guide tells you where to look, but you still need the
hard-to-remember details that usually only show up in older Cocoa writing,
runtime headers, or macOS-specific research.

## How to use these appendices

- Start with Apple for semantics, contracts, and availability.
- Use the blog sources for mental models, debugging strategy, and edge cases.
- Treat every pre-ARC, pre-64-bit, or retired-framework article as something to
  translate before applying.
- Map every external idea back into Garazyk code and tests before changing
  architecture.

## Evidence tags

- `current`: safe as a first stop for current APIs or current platform behavior
- `conceptually useful but dated`: still high-signal, but verify details first
- `historical only`: useful for understanding old techniques, not for direct
  reuse

## Appendix index

| Appendix | Use it when | Main source mix |
| --- | --- | --- |
| [Appendix: Forwarding, NSInvocation, and Proxy Objects](./forwarding-invocation-and-proxies) | a selector is missing, `forwardInvocation:` is involved, or somebody wants `NSProxy` / `NSInvocation` | Apple runtime and archive docs, Mike Ash, Cocoa with Love, NSHipster |
| [Appendix: ARC, Blocks, CF, and Autorelease Boundaries](./arc-blocks-cf-and-autorelease-boundaries) | a bug lives at the seam between ARC objects and callbacks, CoreFoundation, SQLite, or long-running loops | Apple memory/block docs, Mike Ash, Cocoa with Love |
| [Appendix: Runtime Mutation, Associated Objects, Swizzling, and Direct Methods](./runtime-mutation-associated-objects-swizzling-and-direct-methods) | somebody proposes a runtime trick, hidden category state, swizzling, or `objc_direct` | Apple runtime docs, Clang docs, NSHipster, Cocoa with Love |
| [Appendix: KVC, KVO, and Observation Boundaries](./kvc-kvo-and-observation-boundaries) | string-key access, collection proxies, KVO threading, or old Cocoa bindings behavior is in play | Apple KVC/KVO docs, objc.io, Cocoa Is My Girlfriend |
| [Appendix: XPC, Logs, Spotlight, and macOS Investigation](./xpc-logs-spotlight-and-macos-investigation) | the issue is really about macOS process boundaries, logs, metadata, or local platform behavior | Apple XPC/AppKit docs, objc.io, Eclectic Light |

## Why these topics made the cut

These are the places where external research gives Garazyk contributors
something we do not already get from normal code search:

- runtime dispatch edge cases that only make sense once you understand the
  forwarding chain
- ARC-era memory bugs that are really CF, block, or autorelease pool bugs
- runtime mutation techniques that work, but are expensive to debug later
- KVC/KVO rules that create bugs far from the line that looks suspicious
- macOS process and platform behavior that is not visible from Objective-C code
  alone

## Related pages

- [Objective-C Research Patterns & Techniques](../objective_c_tips)
- [Objective-C Research Map](../../11-reference/objective-c-research-map)
- [Troubleshooting](../../11-reference/troubleshooting)
- [Testing Map](../../11-reference/testing-map)

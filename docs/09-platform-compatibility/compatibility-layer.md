---
title: Compatibility Layer
---

# Compatibility Layer

## Overview

Garazyk's compatibility layer is a narrow set of headers, macros, and test shims that keep shared Objective-C code buildable while allowing true platform-specific implementations.

## Full Flow

```mermaid
flowchart TD
    Shared["Shared Objective-C code"]
    Compat["Compat headers and macros"]
    Apple["Apple Foundation and Security APIs"]
    GNU["GNUstep and OpenSSL backed fallbacks"]
    Platform["Platform specific runtime code"]

    Shared --> Compat
    Compat --> Apple
    Compat --> GNU
    Shared --> Platform
```

## What Lives Here Today

The current `Compat/` tree does a few concrete jobs:

- `Compat/Foundation/Foundation.h` selects Apple Foundation or GNUstep Foundation
- `Compat/Foundation/NSDataCompat.*` and `NSErrorCompat.h` paper over GNUstep gaps that shared code depends on
- `Compat/LinuxXCTestCompat.h` keeps the test surface usable on GNUstep
- `Compat/PDSTypes.h` defines CF bridging fallbacks and dispatch-queue storage macros such as `PDS_GCD_OBJC_SUPPORT` and `PDS_DISPATCH_QUEUE_STRONG`

If you need compatibility, check whether one of these files already provides it.

## What It Deliberately Does Not Hide

The compatibility layer does not erase:

- the macOS versus GNUstep networking split
- Keychain versus OpenSSL-backed key-management differences
- runtime differences in dispatch object ownership
- behavior gaps in Foundation implementations

These differences require real platform-specific code, not just macros.

## Contributor Rule Of Thumb

If you add a new cross-platform dependency, prefer one of these approaches:

1. put the smallest possible compatibility shim in `Compat/` when the API gap is narrow and mechanical
2. keep the platform split explicit when the behavior difference is substantial

Avoid sprinkling raw `#if` branches across business logic.

## Related Deep Dives

- [macOS vs GNUstep Boundary](./macos-vs-gnustep-boundary)

## Related Reading

- [macOS and Linux Compatibility](./macos-linux)
- [Platform-Specific Network Transport](./network-transport)
- [Setup](../01-getting-started/setup)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


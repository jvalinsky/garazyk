---
title: "Appendix: ARC, Blocks, CF, and Autorelease Boundaries"
description: Deep research notes for Objective-C ARC edge cases, block capture, CoreFoundation ownership, and autorelease pool use
outline: deep
---

# Appendix: ARC, Blocks, CF, and Autorelease Boundaries

Use this appendix when memory bugs live at the seam between Objective-C objects
and everything Objective-C does not manage for you automatically.

## The ARC mental model that still survives

Mike Ash's ARC article is still the right starting point for a common mistake:
ARC is compiler-inserted retain and release logic, not a general resource
manager.

That distinction matters in Garazyk because many bugs are not "object was
overreleased" bugs. They are:

- callback kept `self` alive too long
- callback did not keep `self` alive long enough
- a CoreFoundation object crossed an ARC boundary unclearly
- a SQLite statement outlived its connection shutdown path
- a background loop held onto autoreleased objects longer than expected

If the resource is not an Objective-C object in the ARC graph, you still own the
teardown contract explicitly.

## Block and `__block` edge cases worth remembering

Apple's archived blocks docs and Cocoa with Love's implementation article still
explain the weird parts best:

- blocks are Objective-C objects
- stack blocks are fast but ephemeral; historically, escaping blocks had to be
  copied to move to the heap
- `__block` variables are shared storage, not snapshots
- that shared storage can move when the block is copied, so do not treat the
  address of a `__block` variable as stable
- referencing an ivar from a block usually means retaining `self`, not merely
  retaining a detached value

Even under ARC, those implementation facts remain useful when a callback behaves
like it captured too much or too little.

## Weak references, delegates, and lifetime graphs

Apple's practical memory guide and Mike Ash's weak-reference piece still make
the key point clearly: weak references solve ownership cycles, not validity by
themselves.

In practice:

- parent-to-child relationships are usually strong
- child-to-parent relationships are usually weak
- delegate-style links should normally be weak
- asynchronous block captures should usually use the weak/strong pattern for
  `self`
- raw pointers, CoreFoundation references, and SQLite handles do not get zeroing
  weak semantics for free

If a path is deferred, queued, or callback-based, treat lifetime as part of the
API contract.

## Autorelease pools are still operationally important

Apple's `Using Autorelease Pool Blocks` article remains directly useful in 2026:

- Foundation-only programs need an autorelease pool around work
- secondary threads need their own autorelease pool
- long loops that create many temporary objects benefit from local
  `@autoreleasepool` blocks

That is especially relevant in server and parser code. If memory rises during a
streaming or import path, the missing fix is often not "add less allocation",
but "drain temporaries sooner."

## What this means for CF, SQLite, and Garazyk resource cleanup

These source-backed rules map directly onto repository work:

- ARC does not release `CFTypeRef` values you own unless you bridge ownership
  explicitly and correctly.
- ARC does not finalize `sqlite3_stmt *` values or close a database handle for
  you.
- ARC does not make incremental parsing safe; buffer ownership and teardown are
  still your problem.
- ARC does not keep queues, sources, or callbacks alive unless the owning object
  graph does.

In Garazyk, this usually becomes a checklist:

- strong queue ownership is explicit
- blocks use weak/strong capture where appropriate
- CF ownership follows create/copy/retain rules
- SQLite shutdown paths finalize statements before close
- long-running loops use local autorelease pools when they produce many
  temporaries

## Research trail

- [Advanced Memory Management Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/MemoryMgmt.html)
  - `conceptually useful but dated`
  - Still the core ownership model, even in ARC-era code.
- [Practical Memory Management](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmPractical.html)
  - `conceptually useful but dated`
  - Good refresher on weak references, ownership graphs, and scarce resources.
- [Using Autorelease Pool Blocks](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html)
  - `conceptually useful but dated`
  - Directly useful for loops, Foundation tools, and secondary threads.
- [Blocks Programming Topics](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Blocks/Articles/00_Introduction.html)
  - `conceptually useful but dated`
  - Good entry point into the block docs set.
- [Blocks and Variables](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Blocks/Articles/bxVariables.html)
  - `conceptually useful but dated`
  - Best official explanation of `__block`, capture rules, and object retention.
- [Automatic Reference Counting](https://mikeash.com/pyblog/friday-qa-2011-09-30-automatic-reference-counting.html)
  - `conceptually useful but dated`
  - Best high-level explanation of what ARC automates.
- [Zeroing Weak References in Objective-C](https://www.mikeash.com/pyblog/friday-qa-2010-07-16-zeroing-weak-references-in-objective-c.html)
  - `conceptually useful but dated`
  - Still useful for understanding what weak references are actually buying you.
- [How blocks are implemented (and the consequences)](https://www.cocoawithlove.com/2009/10/how-blocks-are-implemented-and.html)
  - `conceptually useful but dated`
  - Great for block object model, stack vs heap behavior, and why copy matters.

## Search recipes

```text
site:developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt autorelease weak retain cycle
site:developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Blocks __block block copy capture
site:mikeash.com/pyblog/friday-qa ARC Objective-C weak blocks
site:mikeash.com/pyblog/friday-qa "zeroing weak" Objective-C
site:cocoawithlove.com blocks Objective-C retain cycle __block
site:cocoawithlove.com CoreFoundation Objective-C memory
```

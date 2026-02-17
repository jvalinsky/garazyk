# Objective-C Coding Tips Research Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (via `task` tool) to execute this plan in parallel.

**Goal:** Create an extensive library of Objective-C coding tips to standardize development and share knowledge.

**Architecture:** A set of Markdown guides (or a single comprehensive one) in `docs/guides/objective_c_tips.md`.

**Tech Stack:** Objective-C, Markdown.

## Execution Plan

We will split the research into 4 independent domains to cover the breadth of the language effectively.

### Task 1: Memory Management & Safety
**Agent:** "MemoryAgent"
**Focus:**
- Automatic Reference Counting (ARC) rules.
- Retain cycles: Block capture lists vs Delegate weak references.
- `weak` vs `strong` vs `unsafe_unretained` vs `assign`.
- Autorelease pools (`@autoreleasepool`).
- Proper `init` / `dealloc` patterns.
**Output:** A markdown section "Memory Management Best Practices".

### Task 2: Runtime & Dynamic Features
**Agent:** "RuntimeAgent"
**Focus:**
- The Runtime System: `objc_msgSend`.
- Method Swizzling: Dangers and safe usage (if any).
- Introspection: `isKindOfClass:`, `respondsToSelector:`, `conformsToProtocol:`.
- Associated Objects (`objc_setAssociatedObject`).
- Dynamic typing with `id`.
**Output:** A markdown section "Runtime Power & Responsibility".

### Task 3: Modern Objective-C Features
**Agent:** "ModernAgent"
**Focus:**
- Nullability annotations: `_Nullable`, `_Nonnull`, `_Null_unspecified`.
- Lightweight Generics: `NSArray<NSString *> *`.
- Block syntax, typedefs, and safety.
- Literals: `@[]`, `@{}`.
- Modules (`@import`).
- Grand Central Dispatch (GCD) integration.
**Output:** A markdown section "Modern Objective-C".

### Task 4: Foundation Patterns & Architecture
**Agent:** "PatternAgent"
**Focus:**
- Key-Value Observing (KVO) & Key-Value Coding (KVC): Usage and pitfalls.
- NotificationCenter vs Delegation vs Blocks.
- Categories vs Class Extensions.
- Error Handling: `NSError **` patterns.
- Singleton pattern implementation.
**Output:** A markdown section "Foundation Patterns".

## Resources to Browse
- **Internal Codebase:** `ATProtoPDS/Sources` (Check conventions in `Auth/`, `Database/`, `Network/`).
- **Existing Docs:** `docs/objectivec_networking.md`.
- **External:** Apple Developer Documentation, NSHipster, Objc.io (via web search/fetch).

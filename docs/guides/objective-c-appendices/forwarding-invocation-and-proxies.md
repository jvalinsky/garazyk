---
title: "Appendix: Forwarding, NSInvocation, and Proxy Objects"
description: Deep research notes for Objective-C message forwarding, NSInvocation, NSProxy, and selector debugging
outline: deep
---

# Appendix: Forwarding, NSInvocation, and Proxy Objects

Use this appendix when a bug stops being "a normal missing method" and starts
looking like runtime dispatch, forwarding, or proxy behavior.

For the shorter routing guide, start with
[Objective-C Research Map](../../11-reference/objective-c-research-map). For
the broader cluster summary, use
[Objective-C Research Patterns & Techniques](../objective_c_tips).

## The forwarding chain that actually matters

Mike Ash's forwarding article remains the clearest explanation of what happens
after a method lookup fails. The sequence to keep in your head is:

| Stage | What to verify first | Why it matters |
| --- | --- | --- |
| `+resolveInstanceMethod:` / `+resolveClassMethod:` | was the method supposed to be installed lazily? | this is the only stage that can turn the later send back into an ordinary dispatch |
| `-forwardingTargetForSelector:` | is there exactly one obvious alternate receiver? | fast forwarding is the lowest-overhead redirect |
| `-methodSignatureForSelector:` | can you produce the correct signature for the selector? | without a signature, there is no `NSInvocation` to forward |
| `-forwardInvocation:` | are you forwarding, rewriting, recording, or rejecting the message? | this is where full forwarding lives |
| `-doesNotRecognizeSelector:` | did the lookup really fail, or did your signature/forwarding path fail? | this is the final crash surface, not the root cause |

The most useful debugging habit is to decide which stage you expected to run,
then prove whether it did.

## `NSInvocation` facts people forget

Apple's archived `Using NSInvocation` page is still the best compact reminder of
the parts developers misremember:

- explicit arguments start at index `2`, because indices `0` and `1` are the
  hidden target and selector
- if you cache or reuse an invocation, call `retainArguments`, because the
  target and object arguments are not retained by default
- `NSInvocation` does not support variadic methods or `union` arguments
- the method signature is the contract; if its type encodings are wrong, the
  invocation may forward garbage correctly

That last point is why type encodings matter even if you never call runtime APIs
directly. `NSInvocation`, `NSMethodSignature`, forwarding, and selector
introspection all meet there.

## Patterns that still hold up

- Use fast forwarding when one concrete backing object should receive the
  message unchanged.
- Use full forwarding only when you need to inspect, fan out, rewrite, record,
  or reject the invocation.
- Use `NSProxy` when you truly need a stand-in object with object-like behavior,
  not as a fancier decorator.
- Use `NSInvocation` for infrastructure-style work such as undo, delayed
  invocation, or diagnostic tooling, not for ordinary control flow.

Apple's Cocoa Fundamentals and Design Patterns archive docs are still useful
here: `NSProxy` is a root class for stand-ins and remote-like objects, not a
normal everyday base class.

## Failure modes worth checking first

- The alternate receiver from `forwardingTargetForSelector:` does not actually
  implement the selector you thought it did.
- `methodSignatureForSelector:` returns `nil`, so the runtime never reaches your
  forwarding code.
- The signature exists, but the type encoding is wrong for the real method.
- The code is trying to reason about a direct method or some other non-dynamic
  call path as if it were ordinary Objective-C dispatch.

If that last case is plausible, also read
[Appendix: Runtime Mutation, Associated Objects, Swizzling, and Direct Methods](./runtime-mutation-associated-objects-swizzling-and-direct-methods).

## What this means in September

In this repository, explicit route registration, explicit services, and
straight-line method calls should still win most of the time. This appendix is
useful mainly when you are:

- debugging selector surprises in infrastructure or tools
- reviewing a proposal to add runtime indirection
- figuring out whether a proxy or invocation layer is justified at all

The right question is usually not "can Objective-C do this?" but "why is this
better than an explicit object graph in September?"

## Research trail

- [Objective-C Runtime](https://developer.apple.com/documentation/objectivec/objective-c-runtime)
  - `current`
  - Use for current runtime APIs and low-level inspection boundaries.
- [methodSignatureForSelector:](https://developer.apple.com/documentation/objectivec/nsobject/1571960-methodsignatureforselector)
  - `current`
  - Current API reference for the signature hook full forwarding depends on.
- [Using NSInvocation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DistrObjects/Tasks/invocations.html)
  - `conceptually useful but dated`
  - Best compact reminder about argument indexes, `retainArguments`, and unsupported signatures.
- [Message Encapsulation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DistrObjects/Concepts/messaging.html)
  - `conceptually useful but dated`
  - Good explanation of how `NSInvocation` and `NSMethodSignature` fit together.
- [Cocoa Objects](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaFundamentals/CocoaObjects/CocoaObjects.html)
  - `conceptually useful but dated`
  - Useful background on `NSProxy` as a root class.
- [Cocoa Design Patterns](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaFundamentals/CocoaDesignPatterns/CocoaDesignPatterns.html)
  - `conceptually useful but dated`
  - Helpful when deciding whether you want a proxy or a simpler object relationship.
- [Objective-C Message Forwarding](https://www.mikeash.com/pyblog/friday-qa-2009-03-27-objective-c-message-forwarding.html)
  - `conceptually useful but dated`
  - Still the cleanest explanation of the dispatch-to-forwarding chain.
- [Intro to the Objective-C Runtime](https://www.mikeash.com/pyblog/friday-qa-2009-03-13-intro-to-the-objective-c-runtime.html)
  - `conceptually useful but dated`
  - Best read before the forwarding article if the runtime model feels fuzzy.
- [Construct an NSInvocation for any message, just by sending](https://www.cocoawithlove.com/2008/03/construct-nsinvocation-for-any-message.html)
  - `conceptually useful but dated`
  - Good for understanding how far you can push invocation-based dispatch.
- [Type Encodings](https://nshipster.com/type-encodings/)
  - `conceptually useful but dated`
  - Useful when signatures or runtime inspection stop making sense.

## Search recipes

```text
site:mikeash.com/pyblog/friday-qa "message forwarding" Objective-C
site:mikeash.com/pyblog/friday-qa "Objective-C runtime" isa IMP forwarding
site:cocoawithlove.com NSInvocation Objective-C forwarding
site:nshipster.com "type encodings" Objective-C
site:developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DistrObjects NSInvocation NSMethodSignature
site:developer.apple.com "methodSignatureForSelector:" Objective-C
```

# ADR 0003 — XRPC method registration uses plain NSID constants, not a typed wrapper

**Status:** Accepted
**Date:** 2026-07-11
**Context:** raised during the XRPC NSID constants plan
(`xrpc_nsid_registration_plan.md`), candidate 3 of the architecture review.

## Context

`XrpcHandler` exposes 117 shallow one-line convenience registration methods, and 27 of 34
route packs bypass them to register with raw `@"…"` method-ID literals. The plan replaces both
idioms with a single generated set of method-ID (NSID) constants
(`Network/Generated/GZXrpcNSID.{h,m}`, ~331) emitted from the lexicons, and deletes the 117
convenience methods.

For enforcement — preventing regression to raw literals — two options were weighed:

1. **Plain `NSString * const` NSID constants + a `narzedzia` CI lint** that forbids
   `registerMethod:@"literal"`.
2. **A compile-time-typed `GZNSID` wrapper class**, so `registerMethod:` only accepts `GZNSID`
   and a raw literal becomes a compile error.

The typed wrapper was chosen first (for the hard compile-time guarantee), then reversed after
a cost analysis specific to Objective-C.

## Decision

Use **plain `NSString * const` NSID constants plus the `narzedzia` lint**. Do **not** introduce
a typed `GZNSID` wrapper for XRPC method registration.

## Consequences

- In Objective-C (not Swift), `GZNSID * const X = [GZNSID nsidWithString:@"…"]` is **not a
  constant expression** and will not compile as a `const` global. A wrapper forces the 331
  entries into load-time-initialized mutable globals or 331 accessor functions — re-inflating
  the very surface the plan set out to shrink. Plain `NSString * const` are free compile-time
  literals.
- The dispatcher is irreducibly `NSString`-keyed: `methodHandlers` is
  `NSMutableDictionary<NSString *, XrpcMethodHandler>`, plus `protectedMethods` and lookup by
  the incoming request string. Incoming method-IDs are arbitrary strings with no constant, so
  the read/dispatch/auth path cannot be typed. A wrapper would cover only the ~332
  registration write sites (~2%) and be unwrapped via `.stringValue` immediately.
- Safe use of a wrapper as a dictionary key or with `==` needs interning or `isEqual:`/`hash`
  discipline; `NSString` provides value equality and hashing for free and is already the key
  type.
- Plain constants already make a mistyped constant **name** a compile error (undeclared
  identifier). The only thing the wrapper adds is rejecting a brand-new raw **literal** at
  compile time rather than in CI — which the `narzedzia` lint catches. Net: the wrapper pays
  the above costs to move one drift case from CI to the compiler.

Future architecture / type-safety reviews should **not** re-propose a typed NSID wrapper for
XRPC registration on general "make it type-safe" grounds; the string-keyed dispatcher and
ObjC's constant-expression rules make plain-constants-plus-lint the better trade. Revisit only
if the registration surface moves to Swift, where `NS_TYPED_ENUM` / typed strings enforce
without these costs.

# Auth Middleware Review & Implementation

**Date:** 2026-04-18
**Decision Graph Nodes:** 456, 457
**Commit:** b13149f2
**Plan:** [[~/.letta/plans/2026-04-18-auth-middleware-review.md]]

## Summary

Reviewed authentication middleware architecture and implemented declarative middleware system for XRPC endpoints.

## Key Findings

### Already Implemented

Most requested items were already working:
- ✅ Blob diagnostics (orphan scan, CID verification, consistency check)
- ✅ Admin XRPC endpoints (getServerStats, queryAuditLog, repairRepo)
- ✅ Ozone decoupling (was never coupled)

### Issues Fixed

1. **Blob Audit Compilation** (Node 457)
   - Created `PDSBlobAuditOperation_Protected.h` for subclass access to properties
   - Fixed import paths (PDSDatabase.h contains PDSDatabaseAccount/PDSDatabaseBlob)
   - Fixed CID initialization (`cidFromString:` not `initWithString:`)

2. **Orphaned Code in XrpcAdminMethods.m**
   - Premature `}` at line 529 closed function, orphaning subsequent handlers
   - Removed duplicate updateAccountPassword handler block

## New Implementation: Middleware System

Created declarative middleware infrastructure:

```
XrpcMiddleware.h/.m
├── XrpcMiddleware protocol
├── XrpcMiddlewareChain
├── AuthMiddleware (userAuth, adminAuth)
├── RateLimitMiddleware (perUser, perIP)
└── ResourceOwnershipMiddleware
```

HttpRequest extended with:
- `middlewareContext` - NSMutableDictionary for passing data between middleware
- `authenticatedDid` - Convenience accessor for auth DID

## Remaining Work

- [ ] Update XrpcMethodRegistry to use middleware chains
- [ ] Migrate handlers to use middleware (proof of concept)
- [ ] Deprecate AdminMiddleware
- [ ] Add resource ownership helpers to XrpcAuthHelper

## Files Modified

| File | Change |
|------|--------|
| `Network/XrpcMiddleware.h` | New - middleware protocol definitions |
| `Network/XrpcMiddleware.m` | New - middleware implementations |
| `Network/HttpRequest.h` | Added middlewareContext property |
| `Network/HttpRequest.m` | Added middlewareContext implementation |
| `Admin/Diagnostics/BlobAudit/PDSBlobAuditOperation_Protected.h` | New - protected interface for subclasses |
| `Admin/Diagnostics/BlobAudit/*.m` | Import protected header |
| `Blob/PDSDiskBlobProvider.m` | Fix CID initialization |
| `Network/XrpcAdminMethods.m` | Remove orphaned code |

## Decision Links

- Node 456: Decision to fix blob audit operation compilation
- Node 457: Action - created protected header

## Next Steps

1. Run tests to verify no regressions
2. Wire middleware to XrpcMethodRegistry
3. Migrate 5-10 handlers as proof of concept
4. Document middleware usage patterns

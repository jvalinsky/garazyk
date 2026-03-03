# Lines of Code by Subsystem Report

**Generated:** 2026-03-02
**Git Commit:** 45a6d79f7a42da46932a27b21d055f94af21a029

## Summary

| Subsystem | Lines of Code | Files |
|-----------|---------------|-------|
| Network | 21,281 | 69 |
| Auth | 11,053 | 50 |
| App | 10,453 | 34 |
| Database | 7,644 | 24 |
| CLI | 3,826 | 18 |
| Core | 3,677 | 34 |
| Sync | 3,431 | 16 |
| PLC | 4,198 | 22 |
| Repository | 3,214 | 10 |
| AppView | 2,029 | 12 |
| Lexicon | 2,024 | 12 |
| Admin | 2,106 | 10 |
| Blob | 1,225 | 7 |
| OAuthProvider | 1,113 | 3 |
| Services | 1,116 | 4 |
| AuthCrypto | 999 | 8 |
| Security | 806 | 6 |
| Identity | 835 | 4 |
| Email | 722 | 14 |
| Debug | 676 | 2 |
| Federation | 398 | 2 |
| PDSAuth | 396 | 2 |
| AuthVerifier | 485 | 2 |
| Compat | 213 | 6 |
| Metrics | 217 | 2 |

**Total: 105,102 lines across 369 files**

## Analysis

The Network subsystem (HTTP server, XRPC dispatcher, routing) is by far the largest at ~20% of the codebase, followed by Auth and App. This is typical for a server application where network handling and authentication are complex.

## Methodology

- Counted non-empty, non-comment lines in `.m`, `.h`, `.mm`, `.c`, `.cpp` files
- Excludes test files (in `ATProtoPDS/Tests/`)
- Production code only in `ATProtoPDS/Sources/`

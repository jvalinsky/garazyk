# Group 11-compat-platform: Compat & Platform

## Audit scope
Read every `.h` and `.m` file in the requested Compat/Foundation, Compat/PlatformShims, and top-level Compat directories under `Sources/`.

## Summary
- Files reviewed: 36
- Rating A: 0
- Rating B: 13
- Rating C: 18
- Rating D: 5

### Cross-cutting findings
- No file reached full HeaderDoc coverage (`@abstract`, `@param`, `@return`, `@discussion`) across all documented APIs.
- Most shim headers rely on file-level prose or inline narration rather than API-oriented HeaderDoc.
- Several files are missing `@see` cross-references between shim layers and their underlying CoreFoundation/Security equivalents.
- Multiple comments restate what the code does instead of why the shim exists or what guarantees it provides.
- `SecKey.m` contains the clearest LLM-ism / placeholder-comment problems: hedging, self-corrections, and TODO-style prose.
- Nullability behavior is mostly implied by signatures, not documented in comments.

## File inventory

| File | Quality | Specific issues |
|------|---------|-----------------|
| `Foundation/Foundation.h` | B | File-level HeaderDoc only; missing `@abstract`; no API docs or `@see` cross-references. |
| `Foundation/NSDataCompat.h` | D | No comments at all; no `@file`/`@header` block; public API is undocumented. |
| `Foundation/NSDataCompat.m` | D | No comments at all; implementation behavior is completely undocumented. |
| `Foundation/NSErrorCompat.h` | B | File-level HeaderDoc only; missing `@abstract`; no API docs or `@see` cross-references. |
| `GNUstepCFNetworkCompat.h` | B | File-level HeaderDoc only; missing `@abstract` and `@discussion`; no `@see` cross-references. |
| `LinuxXCTestCompat.h` | B | Class docs exist, but public methods/macros lack `@param`/`@return`; assertion macros are only briefly commented; missing `@see` links. |
| `PDSTypes.h` | B | Macro docs are terse and mostly restate behavior; missing `@abstract`/`@discussion`; no `@see` cross-references. |
| `PlatformShims/CommonCrypto/CommonCrypto.h` | C | Guard comments only; no `@file` block; no HeaderDoc for the shim contract. |
| `PlatformShims/CommonCrypto/CommonCryptor.h` | C | Guard comments only; no HeaderDoc, `@param`, or `@return` docs. |
| `PlatformShims/CommonCrypto/CommonDigest.h` | C | Inline comments only; they narrate wrapper behavior; no HeaderDoc or `@discussion`. |
| `PlatformShims/CommonCrypto/CommonHMAC.h` | C | Guard comments only; no HeaderDoc or API usage notes. |
| `PlatformShims/CommonCrypto/CommonKeyDerivation.h` | C | Guard comments only; no HeaderDoc, `@param`, `@return`, or error semantics docs. |
| `PlatformShims/CoreFoundation/CFBase.h` | C | Inline comments only; many comments restate code paths; no HeaderDoc, `@param`, `@return`, or `@see`; nullability behavior not documented. |
| `PlatformShims/CoreFoundation/CFBase.m` | C | Inline comments only; implementation narration rather than rationale; no HeaderDoc. |
| `PlatformShims/CoreFoundation/CFByteOrder.h` | C | Inline comments only; comments mostly restate conversion code; no HeaderDoc or `@discussion`. |
| `PlatformShims/CoreFoundation/CFNetwork.h` | C | Inline comments only; declarations lack HeaderDoc, `@param`, `@return`, and `@see`. |
| `PlatformShims/CoreFoundation/CFNetwork.m` | C | Inline comments only; parser steps are narrated, not documented as API behavior; no HeaderDoc on public functions. |
| `PlatformShims/CoreFoundation/CFRelease.h` | B | File/macro docs are prose, but not full HeaderDoc; missing `@abstract`, `@param`, `@return`; no `@see` for ownership helpers. |
| `PlatformShims/CoreFoundation/CFTypes.h` | C | Inline comments only; mostly type-order notes; no HeaderDoc or API docs. |
| `PlatformShims/CoreFoundation/CoreFoundation.h` | C | Inline comments only; include-order notes restate code; no HeaderDoc or `@see`. |
| `PlatformShims/LocalAuthentication/LocalAuthentication.h` | D | No comments at all; no file header or API docs. |
| `PlatformShims/LocalAuthentication/LocalAuthentication.m` | D | No comments at all; implementation is completely undocumented. |
| `PlatformShims/Security/SecAccessControl.h` | D | No comments at all; missing file header and API docs. |
| `PlatformShims/Security/SecAccessControl.m` | C | Single inline comment only; no HeaderDoc, no error-domain docs, no `@see`. |
| `PlatformShims/Security/SecItem.h` | B | File header exists, but Linux APIs have only inline headings; public functions missing `@param`/`@return`; constants and error codes undocumented; no `@see`. |
| `PlatformShims/Security/SecItem.m` | B | File header exists, but public functions lack HeaderDoc; comments restate implementation and return codes; missing `@param`/`@return` on all exported APIs. |
| `PlatformShims/Security/SecItemLinuxStore.h` | B | Method docs are decent, but the class doc lacks an explicit `@abstract`; no `@see` to `SecItem*`; nullability/error semantics are not described consistently. |
| `PlatformShims/Security/SecItemLinuxStore.m` | B | File header only; methods are undocumented; inline comments narrate steps (`duplicate`, `serialize`, `merge`) rather than explaining rationale; no `@see`. |
| `PlatformShims/Security/SecKey.h` | B | Class doc is present, but the C API and wrapper methods lack `@param`/`@return`; missing `@see` to the C API; nullability behavior is undocumented. |
| `PlatformShims/Security/SecKey.m` | B | File header only; several comments are conversational/hedging (`Wait`, `Actually`, `For now`); placeholder/TODO-style prose leaks into the implementation; no HeaderDoc on public APIs. |
| `PlatformShims/Security/SecRandom.h` | B | Function docs exist, but `@abstract`/`@discussion` are missing; no `@see`; coverage is incomplete across the shim functions. |
| `PlatformShims/Security/SecRandom.m` | C | Inline comments only; implementation is narrated, not documented; no HeaderDoc on public functions. |
| `PlatformShims/Security/Security.h` | C | Inline comments only; mostly import-order notes; no HeaderDoc or API semantics. |
| `PlatformShims/Stubs/LinuxStubs.m` | C | Single stub comment only; no HeaderDoc; comment is a placeholder rather than documentation. |
| `PlatformShims/libkern/OSAtomic.h` | C | Guard comment only; no HeaderDoc or API docs for the atomic wrappers. |
| `PlatformShims/os/log.h` | C | Only platform-gate inline comments; no HeaderDoc, no `@file`, and macros lack documented behavior. |

## Notes
- This was a read-only audit. No source files were edited.
- The scratchpad file was updated with findings only.

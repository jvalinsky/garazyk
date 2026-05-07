# Group 01-auth-crypto: Auth & Crypto

## Directories
Auth/, Auth/Crypto/, Auth/OAuthProvider/, Auth/PDS/, Auth/Verifier/

## Audit Status
- [x] Audit complete
- [ ] Rewrite complete

## Summary
- Quality split: A=26, B=25, C=14, D=4
- Main issues seen: missing or terse `@param`/`@return` coverage on some public APIs, a few legacy one-line doc comments instead of full HeaderDoc, implementation comments that restate the code instead of explaining intent, and a small set of utility files with little or no formal documentation.
- Scope note: ratings reflect documentation quality only, not runtime correctness.

## File Inventory

### Root Auth/
| File | Quality | Issues |
|------|---------|--------|
| Base32Utils.h | A | Complete HeaderDoc; no material issues. |
| CryptoUtils.h | A | Complete HeaderDoc; minor explanatory overlap in a few utility comments. |
| DPoPUtil.h | B | Good coverage, but a few methods are terse and could use fuller `@param`/`@return` detail. |
| JWT.h | A | Strong API docs; minor nullability prose inconsistency in a few declarations. |
| OAuth2.h | A | Strong HeaderDoc and spec references; some sections are slightly verbose. |
| OAuth2Handler.h | B | Broad coverage, but several methods are only briefly described and some helpers need fuller parameter docs. |
| OAuthServerMetadata.h | A | Clean, concise docs; no material issues. |
| OAuthSession.h | A | Clear model documentation; no material issues. |
| PKCEUtil.h | A | Complete and concise docs; no material issues. |
| Secp256k1.h | A | Strong docs for key generation, signing, and verification primitives. |
| Session.h | B | Mostly documented, but a few lifecycle and nullability details need refinement. |
| TOTPGenerator.h | B | Adequate docs, though some API members are described only at a high level. |
| TOTPService.h | A | Well documented, with clear responsibilities and method summaries. |
| WebAuthnDomain.h | A | Excellent model serialization docs; no material issues. |
| WebAuthnRegistrationHandler.h | A | Complete endpoint-level docs; no material issues. |
| WebAuthnVerifier.h | B | Reasonable coverage, but a few contract details remain implicit. |
| YubiKeyOATH.h | B | Good intent docs, but some public methods need fuller behavioral notes. |
| AuthVerifier.h | B | Mostly documented; several verifier methods need explicit preconditions and return semantics. |

### Auth/Crypto/
| File | Quality | Issues |
|------|---------|--------|
| Crypto/AuthCryptoBase64URL.h | A | Complete HeaderDoc; no material issues. |
| Crypto/AuthCryptoBase64URL.m | B | Clear implementation, but comments are minimal and mostly implementation notes. |
| Crypto/AuthCryptoDPoP.h | A | Strong API docs and clear DPoP intent; no material issues. |
| Crypto/AuthCryptoDPoP.m | A | Strong comments around validation and proof generation; no major issues. |
| Crypto/AuthCryptoECDSA.h | A | Well documented interface; no material issues. |
| Crypto/AuthCryptoECDSA.m | B | Comment coverage is decent, but several methods could use fuller API-level docs. |
| Crypto/AuthCryptoJWK.h | A | Good documentation of JWK primitives; no material issues. |
| Crypto/AuthCryptoJWK.m | B | Mostly explanatory comments; some methods lack explicit return/parameter docs. |

### Auth/OAuthProvider/
| File | Quality | Issues |
|------|---------|--------|
| OAuthProvider/OAuthProvider.h | A | Clear provider contract documentation; no material issues. |
| OAuthProvider/OAuthProvider.m | A | Good docs and spec-oriented comments; no material issues. |
| OAuthProvider/OAuthProviderProtocols.h | A | Protocols are well described and easy to consume. |

### Auth/PDS/
| File | Quality | Issues |
|------|---------|--------|
| PDS/PDSAuth.h | A | Strong API docs and clean role separation; no material issues. |
| PDS/PDSAuth.m | C | Some sections are documented, but several adapters and policy methods lack formal `@param`/`@return` coverage. |
| PDSActorKeyManagerProtocol.h | B | Good coverage, but a few methods need fuller descriptions and nullability notes. |
| PDSAppleActorKeyManager.h | B | Useful API docs, but a few helper behaviors are only briefly described. |
| PDSAppleActorKeyManager.m | C | Inline comments explain mechanics, but public methods and fallback behavior are not consistently documented. |
| PDSAppleKeyManager.h | A | Detailed API docs; a few legacy brief comments remain but nothing major. |
| PDSAppleKeyManager.m | C | Rich inline comments, but several methods restate the code and public API docs are incomplete. |
| PDSKeyManagerFactory.h | A | Very complete HeaderDoc; minor verbosity only. |
| PDSKeyManagerFactory.m | D | Only a file header; no method-level documentation. |
| PDSKeyManagerProtocol.h | B | Protocol is documented, but a few requirements and nullability rules could be clarified. |
| PDSKeyProtocol.h | B | Adequate protocol docs; some properties and methods are only briefly annotated. |
| PDSNonceManager.h | B | Clear intent, but nonce TTL/reuse semantics could be stated more explicitly. |
| PDSNonceManager.m | C | Comments explain TTL/reuse behavior, but public API docs are thin. |
| PDSOpenSSLES256KeyManager.h | B | Solid comments, but style is mostly one-line doc comments rather than full HeaderDoc. |
| PDSOpenSSLES256KeyManager.m | C | Well-commented cryptographic mechanics, but the public surface lacks formal HeaderDoc. |
| PDSOpenSSLKeyManager.h | B | Good legacy-style docs, but not as systematic as the rest of the group. |
| PDSOpenSSLKeyManager.m | C | Minimal documentation; comments are sparse and mostly operational. |
| PDSOpenSSLSessionKeyManager.h | B | Reasonable coverage, but some API members would benefit from richer method-level docs. |
| PDSOpenSSLSessionKeyManager.m | C | Useful inline notes, but the file lacks consistent API-level documentation. |
| PDSReplayCache.h | B | Good docs, though the atomic check-and-add behavior could use more detail. |
| PDSReplayCache.m | C | Good operational comments, but the replay semantics should be documented more explicitly. |

### Auth/Verifier/
| File | Quality | Issues |
|------|---------|--------|
| Verifier/AuthVerifier.h | B | Mostly documented; some verifier methods need more explicit preconditions and return semantics. |
| Verifier/AuthVerifier.m | C | Comments cover intent, but several verification methods need full parameter and return notes. |

### Other root implementation files
| File | Quality | Issues |
|------|---------|--------|
| Base32Utils.m | B | Utility logic is clear, but comment coverage is sparse and mostly operational. |
| CryptoUtils.m | A | Good helper docs and clear purpose; minor inline-comment redundancy only. |
| DPoPUtil.m | C | Public methods are only partially documented; some comments explain code rather than intent. |
| OAuth2.m | A | Very well-commented flow and spec references; a bit verbose in places. |
| OAuth2Handler.m | B | Heavy inline commentary, but several complex methods still lack formal HeaderDoc. |
| OAuthServerMetadata.m | B | Adequate docs, but the implementation is simple and some comments are boilerplate. |
| OAuthSession.m | D | No meaningful documentation beyond code structure. |
| PKCEUtil.m | D | No comments; helper methods are self-explanatory but undocumented. |
| Secp256k1.m | D | No meaningful documentation; the cryptographic API surface is exposed with no narrative. |
| Session.m | B | Model is documented, but a few lifecycle and nullability details need refinement. |
| TOTPGenerator.m | C | Some comments exist, but the public generation/verification flow lacks full method docs. |
| TOTPService.m | A | Thorough API docs and responsibilities are clear; no material issues. |
| WebAuthnDomain.m | B | Clean serialization helpers with modest documentation; some notes are terse. |
| WebAuthnRegistrationHandler.m | C | Endpoint flow is understandable, but the handler methods need formal API docs and error semantics. |
| WebAuthnVerifier.m | B | Reasonable explanatory comments; some method contracts are still implicit. |
| YubiKeyOATH.m | C | Implementation is understandable, but doc coverage is incomplete and partly implementation-oriented. |

### Misc C header
| File | Quality | Issues |
|------|---------|--------|
| secp256k1_wrapper_c.h | C | C API is exposed with sparse commentary; public structs/functions lack higher-level purpose docs. |

## Notes for rewrite phase
- Highest-value rewrite targets: `PKCEUtil.m`, `OAuthSession.m`, `Secp256k1.m`, `PDSKeyManagerFactory.m`, and `WebAuthnRegistrationHandler.m` because they have little or no documentation but are part of public auth flows.
- Secondary cleanup: convert the remaining legacy one-line comments in `PDSOpenSSLKeyManager.*`, `PDSOpenSSLES256KeyManager.*`, and `PDSAppleActorKeyManager.m` into more consistent HeaderDoc where appropriate.
- Keep the cryptography-heavy files focused on purpose and contract, not line-by-line restatement of implementation.

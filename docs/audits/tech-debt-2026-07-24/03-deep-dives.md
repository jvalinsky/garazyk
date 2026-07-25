# Deep Dives

## Candidate 1: PDSAdminService SQL Queries

**Evidence:**
- `PDSAdminService.m:417`: `NSString *codeSQL = [NSString stringWithFormat:@"UPDATE invite_codes SET disabled = 1 WHERE code IN (%@)"...`

**Why it matters:**
Using string interpolation to build SQL queries is an anti-pattern that exposes the application to SQL injection attacks if the formatted arguments are derived from user input. While the current usage might be safe (e.g., if inputs are sanitized upstream or are trusted identifiers), it sets a poor precedent and trips security audits.

**Proposed Refactor Boundary:**
Migrate all string-formatted queries in `PDSAdminService.m`, `FeedService.m`, `GroupService.m`, and `ActorStore.m` to use prepared statements with properly bound parameters. For `IN (...)` clauses, generate the correct number of `?` placeholders dynamically and bind the array elements.

**Characterization Tests Required:**
- SQL injection payload tests for `PDSAdminService` invite code endpoints.
- Regression tests for `FeedService` collection queries.

**Staging and Rollback Notes:**
- Implement in small batches, starting with Admin endpoints.
- Re-run full test suite after each batch. Rollback via git revert if any test fails.

**Confidence:** High

---

## Candidate 2: OAuth2 / DPoP Token Validation

**Evidence:**
- Weak crypto and timing-vulnerable secret comparisons (e.g., `isEqualToString:` instead of constant-time string comparison for secrets).
- Missing DPoP nonce/clock skew handling in some files.

**Why it matters:**
Authentication logic is the most critical security boundary. Using variable-time string comparisons for tokens or hashes allows timing attacks, which can be exploited over the network to leak secrets byte-by-byte.

**Proposed Refactor Boundary:**
Introduce a constant-time string comparison utility (e.g., `PDSConstantTimeCompare`) and replace `isEqualToString:` or `memcmp` used in security-sensitive contexts (`OAuth2.m`, `Session.m`, `JWT.m`, `ATProtoValidator.m`).

**Characterization Tests Required:**
- OAuth2 spec conformance suite.
- DPoP validation test suite.

**Staging and Rollback Notes:**
- Straightforward drop-in replacement for the string comparison function. Low risk of functional regressions.

**Confidence:** High

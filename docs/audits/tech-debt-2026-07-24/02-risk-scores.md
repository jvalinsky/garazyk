# Risk Scores

Ranked scores for candidates based on our evaluation dimensions (Scale: 1-5, 5 being highest).

## 1. PDSAdminService.m & FeedService.m (SQL Injection Risks)
- **Boundary Risk:** 5 (High risk of SQL injection if inputs are unescaped).
- **Structural Drag:** 4 (Raw formatting requires manual review and creates technical debt).
- **Test Leverage:** 4 (Existing test suites likely cover basic queries but not all edge cases).
- **Change Safety:** 3 (Changing queries requires careful regression testing).
- **Refactor Payoff:** 5 (Eliminates critical security vulnerabilities).
- **Overall Score:** 21

## 2. OAuthProvider / JWT (DPoP Conformance & Timing Attacks)
- **Boundary Risk:** 5 (Authentication bypass potential).
- **Structural Drag:** 4 (Complex token lifecycle management).
- **Test Leverage:** 4 (Extensive OAuth and Auth tests available).
- **Change Safety:** 2 (High risk of breaking client authentication).
- **Refactor Payoff:** 5 (Critical for security and spec compliance).
- **Overall Score:** 20

## 3. RelayClient & Firehose (Backpressure and Concurrency)
- **Boundary Risk:** 3 (Internal components, DOS risk).
- **Structural Drag:** 4 (Hard to reason about message flow).
- **Test Leverage:** 3 (Integration tests exist, but hard to simulate exact race conditions).
- **Change Safety:** 3 (Modifying concurrency logic is prone to deadlocks).
- **Refactor Payoff:** 4 (Better stability under load).
- **Overall Score:** 17

## 4. Database Migrations (String formatted table drops)
- **Boundary Risk:** 2 (Mostly static internal constants, low attack surface).
- **Structural Drag:** 2 (Ugly but functional).
- **Test Leverage:** 4 (Migration tests exist).
- **Change Safety:** 4 (Relatively easy to change string formatting to parameterization where applicable).
- **Refactor Payoff:** 3 (Cleaner code, removes false positives from security scans).
- **Overall Score:** 15

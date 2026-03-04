---
title: "Property-Based Test Report"
---

# Property-Based Test Report

Generated: 2026-03-04T02:14:10.411Z

## Summary

- Total Properties: 7
- Passed: 6
- Failed: 1
- Total Iterations: 9722

## Property Results

### Property 1: Complete File Migration

- Status: ✅ PASSED
- Iterations: 302
- Failures: 0

### Property 2: Code Block Preservation

- Status: ❌ FAILED
- Iterations: 3409
- Failures: 80

#### Failure Details

- Code block missing language identifier in documentation-improvement-plan.md:301
- Code block missing language identifier in VERSIONING_STRATEGY.md:152
- Code block missing language identifier in TUTORIAL_COMPILATION_ISSUES.md:27
- Empty code block in MAINTENANCE.md:330
- Empty code block in MAINTENANCE.md:333
- Empty code block in JEKYLL_ARCHIVE.md:204
- Code block missing language identifier in plans/sans-io-refactor.md:529
- Code block missing language identifier in plans/2026-02-17-pluggable-email-resend.md:86
- Code block missing language identifier in plans/2026-02-17-pluggable-email-resend.md:254
- Code block missing language identifier in plans/2026-02-17-pluggable-email-resend.md:552
- Code block missing language identifier in plans/2026-02-17-pluggable-email-resend.md:604
- Code block missing language identifier in plans/2026-02-17-pluggable-email-resend.md:816
- Code block missing language identifier in plans/2026-02-17-pluggable-email-resend.md:1470
- Code block missing language identifier in plans/archive/swift-to-objc-api-translation-guide.md:73
- Code block missing language identifier in plans/archive/swift-to-objc-api-translation-guide.md:131
- Code block missing language identifier in plans/archive/swift-to-objc-api-translation-guide.md:139
- Code block missing language identifier in plans/archive/swift-to-objc-api-translation-guide.md:148
- Code block missing language identifier in plans/archive/plan-2026-01-17T21-07-18Z.md:24
- Code block missing language identifier in plans/archive/objc-api-discovery-implementation.md:213
- Code block missing language identifier in plans/archive/objc-api-discovery-implementation.md:279
- Code block missing language identifier in plans/archive/2026-01-13-gnustep-compatibility-plan.md:168
- Code block missing language identifier in plans/archive/2026-01-09-cryptography-strengthening.md:82
- Code block missing language identifier in plans/archive/2026-01-08-code-review-improvements.md:234
- Code block missing language identifier in plans/archive/2026-01-07-blob-storage.md:277
- Code block missing language identifier in plans/archive/2026-01-07-atproto-scope-requirements.md:687
- Code block missing language identifier in oauth2/security.md:139
- Code block missing language identifier in guides/objective_c_tips.md:189
- Code block missing language identifier in guides/objective_c_tips.md:362
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:29
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:78
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:195
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:289
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:412
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:464
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:552
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:601
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:640
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:792
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:1083
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:1161
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:1594
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:1696
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:1785
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2108
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2231
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2295
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2335
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2420
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2474
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2541
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2648
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2715
- Code block missing language identifier in guides/macOS_Network_Server_Guide.md:2765
- Code block missing language identifier in guides/development/DEVELOPER_GUIDE.md:233
- Code block missing language identifier in guides/development/DEVELOPER_GUIDE.md:321
- Code block missing language identifier in architecture/atproto_data_models.md:13
- Code block missing language identifier in architecture/DIAGRAM_QUICK_REFERENCE.md:72
- Code block missing language identifier in architecture/DIAGRAM_QUICK_REFERENCE.md:132
- Code block missing language identifier in architecture/DIAGRAMS_MERMAID.md:56
- Code block missing language identifier in architecture/ARCHITECTURE_DIAGRAMS.md:248
- Code block missing language identifier in 11-reference/troubleshooting.md:437
- Code block missing language identifier in 11-reference/troubleshooting.md:459
- Code block missing language identifier in 11-reference/test-organization.md:73
- Code block missing language identifier in 11-reference/test-organization.md:87
- Code block missing language identifier in 09-platform-compatibility/arc-runtime.md:271
- Code block missing language identifier in 08-sync-firehose/reconnection-strategy.md:120
- Code block missing language identifier in 08-sync-firehose/reconnection-strategy.md:328
- Code block missing language identifier in 08-sync-firehose/commit-broadcasting.md:300
- Code block missing language identifier in 07-repository-protocol/cid-and-hashing.md:26
- Code block missing language identifier in 07-repository-protocol/cbor-serialization.md:75
- Code block missing language identifier in 07-repository-protocol/cbor-serialization.md:207
- Code block missing language identifier in 07-repository-protocol/blob-garbage-collection.md:133
- Code block missing language identifier in 07-repository-protocol/blob-garbage-collection.md:1372
- Code block missing language identifier in 06-authentication/oauth2-dpop.md:208
- Code block missing language identifier in 04-network-layer/method-registry.md:246
- Code block missing language identifier in 04-network-layer/error-handling.md:417
- Code block missing language identifier in 04-network-layer/domain-methods.md:129
- Code block missing language identifier in 03-application-layer/record-service.md:261
- Code block missing language identifier in 03-application-layer/record-service.md:332
- Code block missing language identifier in 01-getting-started/setup.md:356

#### Counterexamples

```json
[
  {
    "file": "/Users/jack/Software/garazyk/docs/documentation-improvement-plan.md",
    "line": 301,
    "issue": "missing-language"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/VERSIONING_STRATEGY.md",
    "line": 152,
    "issue": "missing-language"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/TUTORIAL_COMPILATION_ISSUES.md",
    "line": 27,
    "issue": "missing-language"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/MAINTENANCE.md",
    "line": 330,
    "issue": "empty"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/MAINTENANCE.md",
    "line": 333,
    "issue": "empty"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/JEKYLL_ARCHIVE.md",
    "line": 204,
    "issue": "empty"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/plans/sans-io-refactor.md",
    "line": 529,
    "issue": "missing-language"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/plans/2026-02-17-pluggable-email-resend.md",
    "line": 86,
    "issue": "missing-language"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/plans/2026-02-17-pluggable-email-resend.md",
    "line": 254,
    "issue": "missing-language"
  },
  {
    "file": "/Users/jack/Software/garazyk/docs/plans/2026-02-17-pluggable-email-resend.md",
    "line": 552,
    "issue": "missing-language"
  }
]
```

### Property 3: Internal Link Validity

- Status: ✅ PASSED
- Iterations: 1696
- Failures: 0

### Property 6: Search Index Coverage

- Status: ✅ PASSED
- Iterations: 302
- Failures: 0

### Property 9: Syntax Highlighting Application

- Status: ✅ PASSED
- Iterations: 3409
- Failures: 0

### Property 12: Heading Hierarchy Consistency

- Status: ✅ PASSED
- Iterations: 302
- Failures: 0

### Property 7: Front Matter Conversion

- Status: ✅ PASSED
- Iterations: 302
- Failures: 0

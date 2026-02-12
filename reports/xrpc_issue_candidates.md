# XRPC Issue Candidates

Generated: 2026-02-12T13:05:54.139Z

Top 30 missing endpoints by priority score.

## 1. [P1] Implement `com.atproto.label.subscribeLabels`

- Namespace: `com.atproto`
- Score: 100
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/label/subscribeLabels.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.label.subscribeLabels` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 2. [P2] Implement `com.atproto.temp.revokeAccountCredentials`

- Namespace: `com.atproto`
- Score: 90
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/temp/revokeAccountCredentials.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.revokeAccountCredentials` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 3. [P2] Implement `com.atproto.admin.getAccountInfo`

- Namespace: `com.atproto`
- Score: 85
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/getAccountInfo.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.getAccountInfo` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 4. [P2] Implement `com.atproto.admin.getAccountInfos`

- Namespace: `com.atproto`
- Score: 85
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/getAccountInfos.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.getAccountInfos` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 5. [P2] Implement `com.atproto.admin.getInviteCodes`

- Namespace: `com.atproto`
- Score: 85
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/getInviteCodes.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.getInviteCodes` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 6. [P2] Implement `com.atproto.admin.deleteAccount`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/deleteAccount.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.deleteAccount` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 7. [P2] Implement `com.atproto.admin.disableAccountInvites`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/disableAccountInvites.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.disableAccountInvites` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 8. [P2] Implement `com.atproto.admin.disableInviteCodes`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/disableInviteCodes.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.disableInviteCodes` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 9. [P2] Implement `com.atproto.admin.enableAccountInvites`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/enableAccountInvites.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.enableAccountInvites` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 10. [P2] Implement `com.atproto.admin.searchAccounts`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/searchAccounts.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.searchAccounts` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 11. [P2] Implement `com.atproto.admin.sendEmail`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/sendEmail.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.sendEmail` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 12. [P2] Implement `com.atproto.admin.updateAccountEmail`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/updateAccountEmail.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.updateAccountEmail` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 13. [P2] Implement `com.atproto.admin.updateAccountHandle`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/updateAccountHandle.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.updateAccountHandle` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 14. [P2] Implement `com.atproto.admin.updateAccountPassword`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/updateAccountPassword.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.updateAccountPassword` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 15. [P2] Implement `com.atproto.admin.updateAccountSigningKey`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/admin/updateAccountSigningKey.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.updateAccountSigningKey` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 16. [P2] Implement `com.atproto.temp.addReservedHandle`

- Namespace: `com.atproto`
- Score: 70
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/temp/addReservedHandle.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.addReservedHandle` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 17. [P2] Implement `com.atproto.temp.checkHandleAvailability`

- Namespace: `com.atproto`
- Score: 70
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/temp/checkHandleAvailability.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.checkHandleAvailability` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 18. [P2] Implement `com.atproto.temp.checkSignupQueue`

- Namespace: `com.atproto`
- Score: 70
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/temp/checkSignupQueue.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.checkSignupQueue` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 19. [P2] Implement `com.atproto.temp.dereferenceScope`

- Namespace: `com.atproto`
- Score: 70
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/temp/dereferenceScope.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.dereferenceScope` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 20. [P2] Implement `com.atproto.temp.fetchLabels`

- Namespace: `com.atproto`
- Score: 70
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/temp/fetchLabels.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.fetchLabels` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 21. [P2] Implement `com.atproto.temp.requestPhoneVerification`

- Namespace: `com.atproto`
- Score: 70
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `ATProtoPDS/Resources/lexicons/com/atproto/temp/requestPhoneVerification.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.requestPhoneVerification` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 22. [P3] Implement `app.bsky.actor.getSuggestions`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/actor/getSuggestions.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.actor.getSuggestions` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 23. [P3] Implement `app.bsky.ageassurance.getConfig`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/ageassurance/getConfig.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.ageassurance.getConfig` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 24. [P3] Implement `app.bsky.ageassurance.getState`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/ageassurance/getState.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.ageassurance.getState` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 25. [P3] Implement `app.bsky.bookmark.getBookmarks`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/bookmark/getBookmarks.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.bookmark.getBookmarks` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 26. [P3] Implement `app.bsky.contact.getMatches`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/contact/getMatches.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.contact.getMatches` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 27. [P3] Implement `app.bsky.contact.getSyncStatus`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/contact/getSyncStatus.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.contact.getSyncStatus` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 28. [P3] Implement `app.bsky.feed.getActorFeeds`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/feed/getActorFeeds.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.feed.getActorFeeds` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 29. [P3] Implement `app.bsky.feed.getFeedGenerator`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/feed/getFeedGenerator.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.feed.getFeedGenerator` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 30. [P3] Implement `app.bsky.feed.getFeedGenerators`

- Namespace: `app.bsky`
- Score: 45
- Phase: Phase 4: Non-core Namespaces
- Lexicon: `ATProtoPDS/Resources/lexicons/app/bsky/feed/getFeedGenerators.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `app.bsky.feed.getFeedGenerators` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.


# XRPC Issue Candidates

Generated: 2026-02-12T07:13:23.738Z

Top 30 missing endpoints by priority score.

## 1. [P0] Implement `com.atproto.repo.listMissingBlobs`

- Namespace: `com.atproto`
- Score: 125
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/repo/listMissingBlobs.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.repo.listMissingBlobs` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 2. [P0] Implement `com.atproto.sync.getRepoStatus`

- Namespace: `com.atproto`
- Score: 125
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/sync/getRepoStatus.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.sync.getRepoStatus` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 3. [P0] Implement `com.atproto.sync.listReposByCollection`

- Namespace: `com.atproto`
- Score: 125
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/sync/listReposByCollection.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.sync.listReposByCollection` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 4. [P0] Implement `com.atproto.identity.requestPlcOperationSignature`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/identity/requestPlcOperationSignature.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.identity.requestPlcOperationSignature` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 5. [P0] Implement `com.atproto.identity.signPlcOperation`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/identity/signPlcOperation.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.identity.signPlcOperation` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 6. [P0] Implement `com.atproto.identity.submitPlcOperation`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/identity/submitPlcOperation.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.identity.submitPlcOperation` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 7. [P0] Implement `com.atproto.identity.updateHandle`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/identity/updateHandle.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.identity.updateHandle` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 8. [P0] Implement `com.atproto.repo.importRepo`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/repo/importRepo.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.repo.importRepo` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 9. [P0] Implement `com.atproto.server.confirmEmail`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/confirmEmail.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.confirmEmail` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 10. [P0] Implement `com.atproto.server.requestAccountDelete`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/requestAccountDelete.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.requestAccountDelete` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 11. [P0] Implement `com.atproto.server.requestPasswordReset`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/requestPasswordReset.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.requestPasswordReset` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 12. [P0] Implement `com.atproto.server.reserveSigningKey`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/reserveSigningKey.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.reserveSigningKey` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 13. [P0] Implement `com.atproto.server.resetPassword`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/resetPassword.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.resetPassword` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 14. [P0] Implement `com.atproto.server.updateEmail`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/updateEmail.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.updateEmail` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 15. [P0] Implement `com.atproto.sync.requestCrawl`

- Namespace: `com.atproto`
- Score: 120
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/sync/requestCrawl.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.sync.requestCrawl` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 16. [P1] Implement `com.atproto.server.getAccountInviteCodes`

- Namespace: `com.atproto`
- Score: 105
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/getAccountInviteCodes.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.getAccountInviteCodes` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 17. [P1] Implement `com.atproto.sync.getCheckout`

- Namespace: `com.atproto`
- Score: 105
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/sync/getCheckout.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.sync.getCheckout` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 18. [P1] Implement `com.atproto.sync.getHostStatus`

- Namespace: `com.atproto`
- Score: 105
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/sync/getHostStatus.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.sync.getHostStatus` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 19. [P1] Implement `com.atproto.sync.listHosts`

- Namespace: `com.atproto`
- Score: 105
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/sync/listHosts.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.sync.listHosts` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 20. [P1] Implement `com.atproto.sync.listRepos`

- Namespace: `com.atproto`
- Score: 105
- Phase: Phase 2: Repository and Sync Completeness
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/sync/listRepos.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.sync.listRepos` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 21. [P1] Implement `com.atproto.identity.refreshIdentity`

- Namespace: `com.atproto`
- Score: 100
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/identity/refreshIdentity.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.identity.refreshIdentity` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 22. [P1] Implement `com.atproto.label.subscribeLabels`

- Namespace: `com.atproto`
- Score: 100
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/label/subscribeLabels.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.label.subscribeLabels` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 23. [P1] Implement `com.atproto.server.requestEmailConfirmation`

- Namespace: `com.atproto`
- Score: 100
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/requestEmailConfirmation.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.requestEmailConfirmation` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 24. [P1] Implement `com.atproto.server.requestEmailUpdate`

- Namespace: `com.atproto`
- Score: 100
- Phase: Phase 1: Identity and Account Safety
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/server/requestEmailUpdate.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.server.requestEmailUpdate` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 25. [P2] Implement `com.atproto.temp.revokeAccountCredentials`

- Namespace: `com.atproto`
- Score: 90
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/temp/revokeAccountCredentials.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.temp.revokeAccountCredentials` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 26. [P2] Implement `com.atproto.admin.getAccountInfo`

- Namespace: `com.atproto`
- Score: 85
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/admin/getAccountInfo.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.getAccountInfo` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 27. [P2] Implement `com.atproto.admin.getAccountInfos`

- Namespace: `com.atproto`
- Score: 85
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/admin/getAccountInfos.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.getAccountInfos` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 28. [P2] Implement `com.atproto.admin.getInviteCodes`

- Namespace: `com.atproto`
- Score: 85
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/admin/getInviteCodes.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.getInviteCodes` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 29. [P2] Implement `com.atproto.admin.deleteAccount`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/admin/deleteAccount.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.deleteAccount` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.

## 30. [P2] Implement `com.atproto.admin.disableAccountInvites`

- Namespace: `com.atproto`
- Score: 80
- Phase: Phase 3: Admin, Label, and Temp APIs
- Lexicon: `/Users/jack/Software/objpds/ATProtoPDS/Resources/lexicons/com/atproto/admin/disableAccountInvites.json`
- Suggested implementation files:
  - `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/App/Services/` (new or existing service)
- Acceptance criteria:
  - Register and route `com.atproto.admin.disableAccountInvites` through XRPC registry.
  - Enforce auth/session checks and input validation.
  - Add successful path test and at least one failure path test.
  - Add/update lexicon conformance assertions for request/response fields.


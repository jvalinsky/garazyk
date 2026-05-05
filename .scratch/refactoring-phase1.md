# Garazyk Refactoring Phase 1: Critical Safety & Concurrency

## Current Focus:
1.1 ARC Invariants & Retain Cycles in `Garazyk/Sources/Auth/OAuth2Handler.m`

## Plan:
- Find all occurrences of blocks in `OAuth2Handler.m` capturing `self`.
- Verify if they create retain cycles (e.g. `validateClient:completion:`).
- Replace with `__weak typeof(self) weakSelf = self;` and `__strong typeof(weakSelf) strongSelf = weakSelf;` if self is used inside.

## Future Items in Phase 1:
- 1.2 Concurrency Primitives (`@synchronized` -> `dispatch_queue_t`) in `OAuth2Handler.m`, `DID.m`, `SubscribeReposHandler.m`, `VideoWorker.m`.
- 1.3 Asynchronous Execution (`dispatch_semaphore_wait` removal) in `XrpcIdentityMethods.m`, `OAuth2Handler.m`, `DID.m`.
- 1.4 Database Re-entrancy Safety (`dispatch_get_specific`) in `AppViewDatabase.m`.
- 1.5 Object Initialization & Defaults in `PDSAuthzManager.h`, `PDSBiometricKeychain.h`, `PDSConfiguration.m`.
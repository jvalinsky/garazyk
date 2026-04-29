# Scratchpad - Fixing Build and Tests

## Current Tasks
- [x] Fix XCTest framework path in CMake
- [x] Fix missing JWTPayload.h import in OAuth2IntrospectionTests
- [x] Fix PDSDatabase init in OAuth2IntrospectionTests
- [x] Fix HttpRequest property assignments in OAuth2IntrospectionTests
- [x] Add missing methods and properties to PDSMigrationManager
- [ ] Resolve PDSMigrationManagerTests build errors
- [ ] Fix PDSMigrationTestFixture errors

## Notes
- PDSMigrationManager had missing monolithic migration support.
- Some tests were using `initWithPath:error:` on PDSDatabase which is not available; switched to `databaseAtURL:` + `openWithError:`.
- HttpRequest properties are readonly, had to use `initWithMethod:...`.
- PDSMigrationManager needs `sharedManager`, `progressBlock`, `cancelBlock`, and migration methods.

## Deciduous Nodes
- Node 411: Fix build issues and test failures in PDSMigrationManager and OAuth2IntrospectionTests.

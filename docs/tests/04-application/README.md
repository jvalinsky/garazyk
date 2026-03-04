---
title: Application Tests
---

# Application Tests

Tests for business logic, controllers, CLI, admin operations, and blob storage.

## Files

| File | Description |
|------|-------------|
| [services.md](services) | Account service, record service, repository service, blob service |
| [controller.md](controller) | Application lifecycle, configuration, service container, account manager |
| [admin.md](admin) | Admin controller, admin service, admin authentication, middleware |
| [cli.md](cli) | CLI dispatcher, account commands, invite commands, service stub |
| [blob.md](blob) | Blob storage, MIME type validation, XRPC blob endpoints |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| PDSApplicationTests | Tests/App/PDSApplicationTests.m | Application lifecycle |
| PDSConfigurationTests | Tests/App/PDSConfigurationTests.m | Configuration loading |
| PDSServiceContainerTests | Tests/Core/PDSServiceContainerTests.m | Dependency injection |
| PDSAccountServiceTests | Tests/App/Services/PDSAccountServiceTests.m | Account CRUD |
| PDSRecordServiceTests | Tests/App/Services/PDSRecordServiceTests.m | Record operations |
| PDSRepositoryServiceTests | Tests/App/Services/PDSRepositoryServiceTests.m | CAR export/sync |
| PDSBlobServiceTests | Tests/App/Services/PDSBlobServiceTests.m | Blob management |
| PDSAdminControllerTests | Tests/Admin/PDSAdminControllerTests.m | Admin operations |
| PDSAdminAuthTests | Tests/Admin/PDSAdminAuthTests.m | Admin auth |
| PDSCLITests | Tests/CLI/PDSCLITests.m | CLI dispatcher |
| BlobStorageTests | Tests/Blob/BlobStorageTests.m | Blob storage |
| MimeTypeValidatorTests | Tests/Blob/MimeTypeValidatorTests.m | MIME validation |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSApplicationTests
./build/tests/AllTests -only-testing:AllTests/PDSAccountServiceTests
./build/tests/AllTests -only-testing:AllTests/PDSCLITests
```

## Related Documentation

- [Test Index](../README) - Main test documentation index
- [ATProto Architecture](../../architecture/atproto_pds_architecture) - System architecture
- [Database Tests](../03-database/README) - Actor stores and pools
- [Security Tests](../05-security/README) - Authorization and validation
- [Integration Tests](../06-integration/README) - E2E application flows
- [Utilities Tests](../09-utilities/README) - Configuration and metrics

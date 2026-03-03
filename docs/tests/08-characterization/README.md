# Characterization Tests

Tests verifying compliance with reference implementations (Go, TypeScript).

## Files

| File | Description |
|------|-------------|
| [characterization.md](characterization) | Reference implementation compliance for actor store, key manager, MST, XRPC |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| ActorStoreCharacterizationTests | Tests/CharacterizationTests/ActorStoreCharacterizationTests.m | Actor store compliance |
| KeyManagerCharacterizationTests | Tests/Auth/KeyManagerCharacterizationTests.m | Crypto compliance |
| SessionCharacterizationTests | Tests/Auth/SessionCharacterizationTests.m | Session compliance |
| MSTCharacterizationTests | Tests/Repository/MSTCharacterizationTests.m | MST compliance |
| XrpcMethodRegistryCharacterizationTests | Tests/Network/XrpcMethodRegistryCharacterizationTests.m | XRPC compliance |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ActorStoreCharacterizationTests
./build/tests/AllTests -only-testing:AllTests/MSTCharacterizationTests
```

## Related Documentation

- [Test Index](../README) - Main test documentation index
- [Characterization Tests](characterization) - Reference compliance details
- [Repository Tests](../01-repository/README) - MST and CAR tests
- [Database Tests](../03-database/README) - Actor store tests
- [Network Tests](../02-network/README) - XRPC tests
- [JWT & Crypto Tests](../00-identity-auth/jwt-crypto) - Key manager tests

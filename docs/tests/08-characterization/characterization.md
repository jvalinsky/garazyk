# Characterization Tests

Tests for reference implementation compliance.

## Test Classes

### ActorStoreCharacterizationTests
**File:** `Tests/CharacterizationTests/ActorStoreCharacterizationTests.m`
**Purpose:** Actor store compliance with reference implementations.

---

### KeyManagerCharacterizationTests
**File:** `Tests/Auth/KeyManagerCharacterizationTests.m`
**Purpose:** Key manager compliance with crypto standards.

---

### SessionCharacterizationTests
**File:** `Tests/Auth/SessionCharacterizationTests.m`
**Purpose:** Session management compliance.

---

### MSTCharacterizationTests
**File:** `Tests/Repository/MSTCharacterizationTests.m`
**Purpose:** MST compliance with Go/TypeScript implementations.

---

### XrpcMethodRegistryCharacterizationTests
**File:** `Tests/Network/XrpcMethodRegistryCharacterizationTests.m`
**Purpose:** XRPC method registry compliance.

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ActorStoreCharacterizationTests
./build/tests/AllTests -only-testing:AllTests/MSTCharacterizationTests
```

## Characterization Test Purpose

Characterization tests verify that the Objective-C implementation produces identical outputs to reference implementations (Go, TypeScript) for the same inputs. They use:

1. **Fixture files** - Reference data from other implementations
2. **Known vectors** - Test vectors from specifications
3. **Cross-validation** - Compare outputs against expected values

This ensures protocol compliance and interoperability across implementations.

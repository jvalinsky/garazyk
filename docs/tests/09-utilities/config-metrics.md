# Configuration & Metrics Tests

Tests for PDS configuration, metrics, and node info.

## Test Classes

### PDSConfigurationTests
**File:** `Tests/App/PDSConfigurationTests.m`
**Purpose:** Configuration loading and environment overrides.

See [Controller Tests](../04-application/controller#pdsconfigurationtests) for full details.

---

### PDSMetricsTests
**File:** `Tests/Metrics/PDSMetricsTests.m`
**Purpose:** Metrics collection and reporting.

---

### NodeInfoTests
**File:** `Tests/App/NodeInfo/NodeInfoTests.m`
**Purpose:** NodeInfo endpoint for server discovery.

---

## Configuration Hierarchy

```
Environment Variables (highest priority)
    ↓
Configuration File (JSON)
    ↓
Default Values (lowest priority)
```

## Key Configuration Options

| Option | Environment | Default |
|--------|-------------|---------|
| HTTP Port | `PDS_PORT` | 2583 |
| Data Directory | `PDS_DATA_DIR` | `./data` |
| Issuer | `PDS_ISSUER` | `http://localhost:2583` |
| Rate Limit (DID) | `PDS_RATE_LIMIT_DID` | 5000/hr |
| Rate Limit (IP) | `PDS_RATE_LIMIT_IP` | 100/min |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSConfigurationTests
./build/tests/AllTests -only-testing:AllTests/NodeInfoTests
```

## Related Documentation

- [Folder README](README) - Utilities tests overview
- [Test Index](../README) - Main test documentation index
- [Debug Tests](debug) - Debug and exploration tools
- [Controller Tests](../04-application/controller) - Configuration loading
- [Application Tests](../04-application/README) - Application lifecycle

# Debug & Exploration Tests

Tests for debug handlers, MST viewer, and logging utilities.

## Test Classes

### PDSLoggerPerformanceTests
**File:** `Tests/Debug/PDSLoggerPerformanceTests.m`
**Purpose:** Logger performance benchmarks.

---

### ExploreHandlerTests
**File:** `Tests/App/ExploreHandlerTests.m`
**Purpose:** Explore/debug endpoint handlers.

---

### ExploreCacheTests
**File:** `Tests/App/ExploreCacheTests.m`
**Purpose:** Explore data caching.

---

### MSTViewerHandlerTests
**File:** `Tests/App/MSTViewerHandlerTests.m`
**Purpose:** MST visualization/debug endpoint.

---

### OAuthDemoHandlerConfigurationTests
**File:** `Tests/App/OAuthDemo/OAuthDemoHandlerConfigurationTests.m`
**Purpose:** OAuth demo handler configuration.

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSLoggerPerformanceTests
./build/tests/AllTests -only-testing:AllTests/ExploreHandlerTests
./build/tests/AllTests -only-testing:AllTests/MSTViewerHandlerTests
```

## Debug Endpoints

| Path | Purpose |
|------|---------|
| `/explore` | Debug explore UI |
| `/mst-viewer` | MST visualization |
| `/oauth/demo` | OAuth flow demo |

## Related Documentation

- [Folder README](README) - Utilities tests overview
- [Test Index](../README) - Main test documentation index
- [Config & Metrics Tests](config-metrics) - Configuration and metrics
- [Repository Tests](../01-repository/mst) - MST visualization
- [OAuth Tests](../00-identity-auth/oauth) - OAuth demo
- [HTTP Stack Tests](../02-network/http-stack) - HTTP routing

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

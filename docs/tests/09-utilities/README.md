---
title: Utilities Tests
---

# Utilities Tests

Tests for configuration, metrics, debugging tools, and exploration endpoints.

## Files

| File | Description |
|------|-------------|
| [config-metrics.md](config-metrics) | Configuration hierarchy, environment overrides, metrics collection, NodeInfo |
| [debug.md](debug) | Logger performance, explore handler, MST viewer, OAuth demo |

## Test Classes

| Class | File Location | Purpose |
|-------|---------------|---------|
| ATProtoServiceConfigurationTests | Tests/App/ATProtoServiceConfigurationTests.m | Config loading |
| PDSMetricsTests | Tests/Metrics/PDSMetricsTests.m | Metrics collection |
| NodeInfoTests | Tests/App/NodeInfo/NodeInfoTests.m | Server discovery |
| PDSLoggerPerformanceTests | Tests/Debug/PDSLoggerPerformanceTests.m | Logger benchmarks |
| ExploreHandlerTests | Tests/App/ExploreHandlerTests.m | Debug UI |
| MSTViewerHandlerTests | Tests/App/MSTViewerHandlerTests.m | MST visualization |
| ExploreCacheTests | Tests/App/ExploreCacheTests.m | Cache layer |
| OAuthDemoHandlerConfigurationTests | Tests/App/OAuthDemo/OAuthDemoHandlerConfigurationTests.m | OAuth demo |

## Running Tests

```bash
./build/tests/AllTests -only-testing:AllTests/ATProtoServiceConfigurationTests
./build/tests/AllTests -only-testing:AllTests/NodeInfoTests
./build/tests/AllTests -only-testing:AllTests/ExploreHandlerTests
```

## Related Documentation

- [Test Index](../README) - Main test documentation index
- [Config & Metrics Tests](config-metrics) - Configuration details
- [Debug Tests](debug) - Debug and exploration tools
- [Application Tests](../04-application/README) - Application lifecycle
- [Controller Tests](../04-application/controller) - Configuration loading

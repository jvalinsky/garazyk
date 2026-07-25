# Schemat: Topology Compilation, Docker Compose YAML Gen — Research Plan

## Package Summary
Deterministic Docker Compose topology definitions for AT Protocol networks. Defines service roles, compiles presets into compose YAML, writes manifests. No filesystem I/O at module load.

## Key Techniques
1. **Topology preset system** — `TopologyPreset` with role inheritance (`InheritedAdapter`)
2. **Docker Compose YAML generation** — Manual string concatenation (no YAML library)
3. **Topology compilation pipeline** — validate → resolve → render → write
4. **Path traversal protection** — `renderVolume()` and sidecar config file path validation
5. **Capability registry** — `CAPABILITY_REGISTRY` with role-capability validation
6. **Topology manifest** — Versioned JSON manifest (v1/v2) for runtime consumption
7. **SigNoz OTel infrastructure** — Optional ClickHouse + Zookeeper + OTel Collector + SigNoz UI
8. **Authoring DSL** — `defineTopology()`, `role()`, `health()`, `port()`, `source()`, `volume()`

## Research Queries (for sub-agents)

### Q1: Docker Compose YAML generation without a library
- Search: "Docker Compose YAML generation JavaScript string concatenation pitfalls"
- Search: "Docker Compose YAML spec edge cases service names special characters"
- Focus: Risks of manual YAML generation — quoting issues, special characters in env values, multiline strings, boolean coercion

### Q2: Docker Compose health check best practices
- Search: "Docker Compose healthcheck curl vs wget best practices"
- Search: "Docker Compose healthcheck start_period retries interval tuning"
- Focus: The code uses `curl -f` for health checks — is `wget --spider` better? Are the interval/timeout/retry values optimal?

### Q3: Topology preset inheritance patterns
- Search: "configuration inheritance resolution patterns TypeScript"
- Search: "Docker Compose extends vs override patterns"
- Focus: The `InheritedAdapter` pattern — how does it compare to Docker Compose `extends`? Are there circular inheritance risks?

### Q4: Path traversal prevention in Docker volume mounts
- Search: "Docker volume mount path traversal security"
- Search: "Docker Compose volume source path validation best practices"
- Focus: The `renderVolume()` path traversal check — is `relative()` + `startsWith("..")` sufficient? Symlink attacks?

### Q5: SigNoz OTel stack configuration
- Search: "SigNoz Docker Compose configuration best practices 2025"
- Search: "OTel Collector Docker Compose health check configuration"
- Focus: Are the SigNoz image versions pinned correctly? Is the OTel Collector config mounted correctly?

### Q6: Topology manifest versioning strategy
- Search: "configuration manifest versioning backward compatibility"
- Search: "JSON manifest version migration strategy"
- Focus: The v1/v2 manifest format — is the versioning strategy sustainable? How to handle v3?

## Code Review Concerns to Investigate
- Manual YAML generation — no quoting for env values containing `:` or `#` characters
- `renderComposeYaml()` uses `Record<string, any>` extensively — type safety gaps
- `validatePreset()` doesn't check for circular inheritance chains
- `extractContainerPort()` takes the first port mapping — may not always be the health check port
- SigNoz services are hardcoded in `renderSigNozServices()` — not configurable
- `composeDown()` doesn't check exit code — silently ignores failures
- `compileTopology()` writes files before validation completes in some paths
- `roleEnvKey()` maps roles to env var names — but the mapping is implicit and not validated

## Deciduous Link
- Node 283: schemat action

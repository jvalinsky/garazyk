# Build System Integration

## Table of Contents

- [CMake (Source of Truth)](#cmake-source-of-truth)
- [XcodeGen (CMake Wrapper)](#xcodegen-cmake-wrapper)
- [Docker Integration](#docker-integration)
- [Full Edit Checklist](#full-edit-checklist)

## CMake (Source of Truth)

CMake defines the real executable and library graph. XcodeGen wraps it.

### Add a New Service Binary

Edit `CMakeLists.txt` at the root. Add after the existing binary targets:

```cmake
# ── <service-name> ──────────────────────────────────────────────────────────

add_executable(<service-name>
  Garazyk/Binaries/<service-name>/main.m
)

target_include_directories(<service-name> PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources
  ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Frameworks
  ${SECP256K1_INCLUDE_DIRS}
)

if(APPLE)
  target_link_libraries(<service-name> PRIVATE
    ATProtoTransport
    ATProtoXRPC
    ATProtoCore
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
else()
  target_link_libraries(<service-name> PRIVATE
    -Wl,--whole-archive
    ATProtoTransport
    ATProtoXRPC
    ATProtoCore
    -Wl,--no-whole-archive
    ${PLATFORM_LIBRARIES}
    ${SECP256K1_LIBRARIES}
  )
endif()

target_compile_definitions(<service-name> PRIVATE
  SQLITE_THREADSAFE=2
)

set_target_properties(<service-name> PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LINK_FLAGS "-ObjC"
)
```

### Static Library Linking Guide

**Minimal (HTTP + XRPC, no DB):**
```
ATProtoTransport ATProtoXRPC ATProtoCore
```

**With database:**
```
ATProtoStorage ATProtoTransport ATProtoXRPC ATProtoCore
```

**With services (account, blob, identity):**
```
ATProtoServices ATProtoStorage ATProtoTransport ATProtoXRPC ATProtoCore
```

**With sync/firehose:**
```
ATProtoSync ATProtoServices ATProtoStorage ATProtoTransport ATProtoXRPC ATProtoCore
```

**Full PDS-like:**
```
ATProtoAppViewServer ATProtoRuntime ATProtoVideoService ATProtoServices
ATProtoTransport ATProtoXRPC ATProtoSync ATProtoStorage ATProtoPLC ATProtoCore
ATProtoRuntime ATProtoPLC   ← repeated for macOS static archive ordering
```

### macOS Linking Notes

- `LINK_FLAGS "-ObjC"` is **required** on all service binaries — pulls in ObjC category methods from static libs
- Some targets repeat `ATProtoRuntime` and `ATProtoPLC` at the end to satisfy circular dependencies in static archive ordering
- `-Wl,--whole-archive` is **not used** on macOS (the linker handles it differently)

### Linux Linking Notes

- Wrap static libs in `-Wl,--whole-archive ... -Wl,--no-whole-archive` to force GNU ld to pull in all symbols
- `+load` methods in unreferenced static archive objects are stripped on Linux — use explicit registration calls instead
- `curl_global_init(CURL_GLOBAL_ALL)` must be called in `main.m` on Linux

### Adding Source Files to a Static Lib

Source files are automatically picked up by glob patterns in CMakeLists.txt. The patterns are:

| Static Lib | Source Pattern |
|-----------|---------------|
| `ATProtoCore` | `Sources/Core/*.m`, `Sources/Compat/*.m`, `Sources/Debug/*.m`, `Sources/Metrics/*.m`, `Sources/Auth/Crypto/*.m`, `Sources/Auth/Verifier/*.m`, `Sources/Security/*.m`, `Sources/Lexicon/*.m` |
| `ATProtoStorage` | `Sources/Database/*.m`, `Sources/Repository/*.m`, `Sources/Core/Repositories/*.m` |
| `ATProtoServices` | `Sources/Auth/*.m` (excl. Crypto/Verifier/PDS), `Sources/Blob/*.m`, `Sources/Email/*.m`, `Sources/Identity/*.m`, `Sources/Services/*.m`, `Sources/Admin/*.m`, `Sources/AppView/*.m` (excl. Server), `Sources/Chat/*.m`, `Sources/Ozone/*.m`, `Sources/Federation/*.m`, `Sources/Registration/*.m`, `Sources/PhoneVerification/*.m`, `Sources/Germ/*.m` |
| `ATProtoTransport` | `Sources/Network/*.m` (excl. Xrpc*, RoutePacks, ServerBuilder) |
| `ATProtoXRPC` | `Sources/Network/Xrpc*.m`, `Sources/Network/ATProtoHttpXrpcRoutePack.m`, `Sources/Network/RelayXrpcRoutePack.m`, `Sources/Network/AppViewXRpcRoutePack.m` |
| `ATProtoSync` | `Sources/Sync/Firehose/*.m`, `Sources/Sync/Relay/*.m`, `Sources/Sync/WebSocket/*.m` |
| `ATProtoPLC` | `Sources/PLC/*.m` |
| `ATProtoRuntime` | `Sources/App/*.m`, `Sources/CLI/*.m`, `Sources/Auth/PDS/*.m`, `Sources/Network/ATProtoHttpServerBuilder.m` |
| `ATProtoVideoService` | `Sources/Video/*.m` |
| `ATProtoAppViewServer` | `Sources/AppView/Server/*.m` (excl. Binary/) |

**New route packs** added to `Sources/Network/` must be explicitly added to `ATProtoXRPC` sources in CMake if they don't match the existing glob patterns.

### Adding a New Static Library

If the service needs its own module library:

```cmake
# Define source list
set(ATPROTO_<MODULE>_SOURCES
  Garazyk/Sources/<Module>/*.m
)

# Create the library
add_library(ATProto<Module> STATIC ${ATPROTO_<MODULE>_SOURCES})

# Add to the module targets list for shared include/compile settings
list(APPEND PDS_MODULE_TARGETS ATProto<Module>)

# Set dependencies
target_link_libraries(ATProto<Module> PUBLIC ATProtoCore)
```

## XcodeGen (CMake Wrapper)

Edit `project.yml`. Add a tool target that wraps CMake:

```yaml
<service-name>:
  type: tool
  platform: macOS
  sources: []
  settings:
    base:
      PRODUCT_NAME: <service-name>
      INFOPLIST_FILE: Garazyk/Resources/Info.plist
      MACOSX_DEPLOYMENT_TARGET: "14.0"
      EXECUTABLE_PATH: "$(PROJECT_DIR)/build/bin/<service-name>"
  prebuildScripts:
      - name: "Build with CMake"
        basedOnDependencyAnalysis: false
        script: |
          #!/bin/bash
          set -e
          mkdir -p "${PROJECT_DIR}/build"
          cd "${PROJECT_DIR}/build"
          XCODE_CLANG="$(xcrun -find clang)"
          XCODE_CLANGXX="$(xcrun -find clang++)"
          cmake .. \
            -DCMAKE_BUILD_TYPE=${CONFIGURATION} \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
            -DCMAKE_C_COMPILER="${XCODE_CLANG}" \
            -DCMAKE_CXX_COMPILER="${XCODE_CLANGXX}" \
            -DCMAKE_OBJC_COMPILER="${XCODE_CLANG}" \
            -DCMAKE_OBJCXX_COMPILER="${XCODE_CLANGXX}" \
            -DBUILD_SECP256K1=ON \
            -DBUILD_TESTS=OFF \
            -DBUILD_FUZZERS=OFF
          cmake --build . --target <service-name> --parallel $(sysctl -n hw.ncpu)
```

Copy the prebuild script from an existing target — they're all identical except the `--target` name.

## Docker Integration

### 1. `docker/Dockerfile.gnustep`

**Build stage** — add the target to the `cmake --build` line:
```dockerfile
RUN cmake --build . --target kaszlak --target campagnola --target zuk --target syrena --target garazyk-ui --target jelcz --target syrena-chat --target germ --target <service-name> --parallel $(nproc)
```

**Runtime stage** — add COPY line:
```dockerfile
COPY --from=builder /src/build/bin/<service-name> /usr/local/bin/<service-name>
```

### 2. `scripts/stage-docker-binaries.sh`

Add to the `BINARIES` array:
```bash
BINARIES=(kaszlak campagnola zuk syrena garazyk-ui jelcz syrena-chat germ <service-name>)
```

### 3. `docker/local-network/Dockerfile.local`

Add COPY line:
```dockerfile
COPY staging/bin/<service-name> /usr/local/bin/<service-name>
```

### 4. `docker/local-network/docker-compose.yml` (if used locally)

Add a service container:
```yaml
local-<service-name>:
  build:
    context: .
    dockerfile: Dockerfile.local
  entrypoint: ["/usr/local/bin/<service-name>"]
  command:
    - "serve"
    - "--port"
    - "<port>"
    - "--data-dir"
    - "/var/lib/atprotopds"
  ports:
    - "<port>:<port>"
  volumes:
    - local_<service-name>_data:/var/lib/atprotopds
  depends_on:
    local-plc:
      condition: service_healthy
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:<port>/xrpc/com.atproto.server.describeServer"]
    interval: 5s
    timeout: 3s
    retries: 10
    start_period: 15s
  networks:
    - local_net
```

Add volume:
```yaml
volumes:
  local_<service-name>_data:
```

### 5. `scripts/lib/common.sh`

Add service port/URL/binary/health variables:
```bash
SERVICE_PORT_<SERVICE>="${<SERVICE>_PORT:-<port>}"
SERVICE_URL_<SERVICE>="http://127.0.0.1:$SERVICE_PORT_<SERVICE>"
SERVICE_BINARY_<SERVICE>="<service-name>"
SERVICE_HEALTH_<SERVICE>="/xrpc/com.atproto.server.describeServer"
```

## Full Edit Checklist

When adding a new service, edit these files:

- [ ] `Garazyk/Binaries/<name>/main.m` — new entry point
- [ ] `Garazyk/Sources/<Module>/` — runtime class + domain logic
- [ ] `Garazyk/Sources/Network/<Name>XrpcRoutePack.{h,m}` — route pack
- [ ] `CMakeLists.txt` — add_executable + link libs
- [ ] `project.yml` — XcodeGen tool target
- [ ] `docker/Dockerfile.gnustep` — build target + COPY
- [ ] `scripts/stage-docker-binaries.sh` — BINARIES array
- [ ] `docker/local-network/Dockerfile.local` — COPY
- [ ] `docker/local-network/docker-compose.yml` — service container (if local)
- [ ] `scripts/lib/common.sh` — service port/URL/binary variables
- [ ] `Garazyk/Tests/` — test files
- [ ] `Garazyk/Tests/test_main.m` — test registration

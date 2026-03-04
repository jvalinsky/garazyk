---
title: Setup Guide
---

# Setup Guide

## Prerequisites

### macOS

**Required:**
- macOS 14.0 or later
- Xcode 16.1 or later (includes clang compiler)
- CMake 3.28 or later
- Git

**Installation:**

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install CMake via Homebrew
brew install cmake

# Verify installations
cmake --version
clang --version
```

## Linux (GNUstep)

**Required:**
- Ubuntu 24.04 LTS or similar
- GNUstep Make and Base libraries
- Clang compiler
- CMake 3.28 or later
- Git

**Installation:**

```bash
# Update package manager
sudo apt-get update

# Install build tools
sudo apt-get install -y \
  clang \
  cmake \
  ninja-build \
  git

# Install GNUstep
sudo apt-get install -y \
  gnustep-make \
  libgnustep-base-dev \
  libblocksruntime-dev \
  gnustep-devel \
  libdispatch-dev \
  uuid-dev

# Install dependencies
sudo apt-get install -y \
  libssl-dev \
  libsqlite3-dev \
  libqrencode-dev

# Verify installations
cmake --version
clang --version
gnustep-config --version
```

### Note on Foundation Frameworks

Keep in mind that while macOS uses Apple's native `Foundation.framework`, Linux builds link against `GNUstep Base`. You may need to use conditional compilation flags (e.g., `#if defined(__APPLE__)`) when dealing with very new macOS APIs (like `os_log`) that are not present in the GNUstep implementation.

## Building from Source

### macOS Build

**Step 1: Clone the repository**

```bash
git clone https://github.com/garazyk/atproto-pds.git
cd atproto-pds
```

**Step 2: Create build directory**

```bash
mkdir -p build
cd build
```

**Step 3: Configure with CMake**

```bash
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_OBJC_COMPILER=clang \
  -DBUILD_SECP256K1=ON \
  -DBUILD_TESTS=ON
```

**Step 4: Build**

```bash
make -j$(sysctl -n hw.ncpu)
```

**Step 5: Run tests**

```bash
./tests/AllTests
```

**Step 6: Start the server**

```bash
./bin/kaszlak --data-dir ../pds-data --config ../config.json
```

### Linux Build

**Step 1: Clone the repository**

```bash
git clone https://github.com/garazyk/atproto-pds.git
cd atproto-pds
```

**Step 2: Create build directory**

```bash
mkdir -p build-linux
cd build-linux
```

**Step 3: Configure with CMake**

```bash
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_OBJC_COMPILER=clang \
  -DBUILD_SECP256K1=ON \
  -DBUILD_TESTS=ON
```

**Step 4: Build**

```bash
make -j$(nproc)
```

**Step 5: Run tests**

```bash
./tests/AllTests
```

**Step 6: Start the server**

```bash
./bin/kaszlak --data-dir ../pds-data --config ../config.json
```

## Using Xcode (macOS)

For development with Xcode IDE:

**Step 1: Generate Xcode project**

```bash
xcodegen generate
```

**Step 2: Open in Xcode**

```bash
open ATProtoPDS.xcodeproj
```

**Step 3: Build**

```bash
xcodebuild -scheme ATProtoPDS-CLI build
```

**Step 4: Run tests**

```bash
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

## Configuration

### Creating a Configuration File

Create `config.json` in the repository root:

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "issuer": "https://localhost:2583"
  },
  "database": {
    "path": "./pds-data/db"
  },
  "plc": {
    "url": "https://plc.directory"
  },
  "session": {
    "invite_code_required": false
  },
  "debug": {
    "verbose": true,
    "log_level": "debug"
  }
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `server.host` | string | `0.0.0.0` | Server bind address |
| `server.port` | number | `2583` | Server port |
| `server.issuer` | string | Required | Server DID or URL |
| `database.path` | string | `./pds-data/db` | Database directory |
| `plc.url` | string | `https://plc.directory` | PLC directory URL |
| `rate_limit.enabled` | boolean | `true` | Enable rate limiting |
| `session.invite_code_required` | boolean | `true` | Require invite codes |
| `debug.verbose` | boolean | `false` | Verbose logging |
| `debug.log_level` | string | `info` | Log level (debug, info, warn, error) |

## Running the Server

### Development Mode

```bash
# macOS
./build/bin/kaszlak --data-dir ./pds-data --config ./config.json --verbose

# Linux
./build-linux/bin/september --data-dir ./pds-data --config ./config.json --verbose
```

## Production Mode

For production deployment, see [Production Deployment Guide](../10-tutorials/tutorial-6-deployment).

## Verifying Installation

### Check Server Health

```bash
# In another terminal, after starting the server
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer | jq .
```

Expected response:

```json
{
  "did": "did:web:localhost:2583",
  "availableUserDomains": ["localhost"],
  "inviteCodeRequired": false,
  "phoneNumberRequired": false,
  "links": {
    "privacyPolicy": "https://localhost:2583/privacy",
    "termsOfService": "https://localhost:2583/terms"
  }
}
```

## Create a Test Account

```bash
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "handle": "test.localhost",
    "password": "test-password-123"
  }' | jq .
```

## Troubleshooting

### Build Failures

**CMake not found:**
```bash
# macOS
brew install cmake

# Linux
sudo apt-get install cmake
```

**Clang not found:**
```bash
# macOS
xcode-select --install

# Linux
sudo apt-get install clang
```

**GNUstep not found (Linux):**
```bash
sudo apt-get install gnustep-make libgnustep-base-dev
```

## Runtime Issues

**Port already in use:**
```bash
# Find process using port 2583
lsof -i :2583

# Kill the process
kill -9 <PID>

# Or use a different port in config.json
```

**Database locked:**
```bash
# Remove lock file
rm -f ./pds-data/db/*.lock

# Restart server
```

**Permission denied:**
```bash
# Ensure data directory is writable
chmod -R 755 ./pds-data
```

## Development Workflow

### Building During Development

Use the provided build script for a clean rebuild:

```bash
./scripts/wipe_and_rebuild.sh
```

### Running Tests

```bash
# All tests
./build/tests/AllTests

# Specific test class
./build/tests/AllTests -XCTest MSTInteropTests

# Multiple test classes
./build/tests/AllTests -XCTest MSTInteropTests,CARInteropTests
```

## Code Quality Checks

```bash
# ShellCheck all scripts
shellcheck scripts/*.sh

# Find TODO/FIXME markers
./scripts/stub_find.sh .
```

## Docker Setup (Optional)

For containerized development:

```bash
# Build Docker image
docker build -f docker/Dockerfile.gnustep -t atprotopds:dev .

# Run container
docker run -it \
  -p 2583:2583 \
  -v $(pwd)/pds-data:/data \
  atprotopds:dev
```

## Next Steps

- **[Architecture Overview](architecture-overview)** — Understand system design
- **[Core Concepts](../02-core-concepts/atproto-basics)** — Learn AT Protocol basics
- **[Tutorials](../10-tutorials/tutorial-1-hello-pds)** — Hands-on learning
- **[Reference](../11-reference/cli-reference)** — CLI command reference

## Getting Help

- **GitHub Issues** — Report bugs and request features
- **GitHub Discussions** — Ask questions and discuss ideas
- **Documentation** — Check the full documentation guide
- **Contributing** — See CONTRIBUTING.md for development guidelines

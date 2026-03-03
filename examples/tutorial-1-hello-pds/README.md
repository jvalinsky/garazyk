# Tutorial 1: Hello PDS - Minimal Example

This is a minimal, self-contained PDS example that demonstrates basic server setup and request handling.

## What This Example Shows

- Creating a `PDSApplication` instance
- Configuring the HTTP server
- Starting the server and handling requests
- Testing with `curl`

## Prerequisites

- Xcode 16.1+ (macOS) or GNUstep (Linux)
- CMake 3.21+
- Basic Objective-C knowledge

## Building

This example is designed to be built as part of the main PDS project. To build it:

### Option 1: Build with the main project (Recommended)

```bash
# From the repo root
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)

# The hello-pds binary will be in ./bin/
./bin/hello-pds
```

### Option 2: Build standalone (macOS only)

If you want to build just this example:

```bash
# From the example directory
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)

# Run
./hello-pds
```

## Running

Once the server starts, you'll see:

```
✓ PDS initialized
✓ Server started on port 2583

Test the server with:
  curl http://localhost:2583/xrpc/com.atproto.server.describeServer

Press Ctrl+C to stop
```

## Testing

In another terminal, test the server:

```bash
# Test the describeServer endpoint
curl http://localhost:2583/xrpc/com.atproto.server.describeServer

# Expected output:
# {
#   "did": "did:web:localhost:2583",
#   "availableUserDomains": ["localhost"],
#   "inviteCodeRequired": false,
#   "phoneNumberRequired": false
# }
```

## Troubleshooting

### Port Already in Use

If you get "Address already in use" error:

```bash
# Find process using port 2583
lsof -i :2583

# Kill the process
kill -9 <PID>
```

### Build Errors

If you encounter build errors:

```bash
# Clean and rebuild
rm -rf build
mkdir build && cd build
cmake ..
make
```

### CMake Not Found

Install CMake:

**macOS:**
```bash
brew install cmake
```

**Linux:**
```bash
sudo apt-get install cmake
```

## Code Structure

- `src/main.m` — Entry point demonstrating PDS initialization
- `CMakeLists.txt` — Build configuration

## Key Components

### PDSApplication

The main application facade that:
- Manages all services (account, record, blob, repository)
- Provides the HTTP server
- Handles database initialization
- Manages the application lifecycle

### HttpServer

The HTTP server that:
- Listens on port 2583
- Routes XRPC requests
- Handles request/response serialization

### Configuration

The `PDSConfiguration` object that:
- Sets the server port
- Configures the issuer DID
- Manages database paths
- Controls debug options

## Next Steps

- **Tutorial 2: Account Management** — Add account creation
- **Tutorial 3: Record Operations** — Add record CRUD
- **Tutorial 4: Authentication** — Add JWT tokens

## Architecture

```
┌─────────────────────────────────────────┐
│         HTTP Client (curl)              │
└────────────────┬────────────────────────┘
                 │
        ┌────────▼────────┐
        │   HttpServer    │
        │  (Port 2583)    │
        └────────┬────────┘
                 │
        ┌────────▼────────────────┐
        │  XrpcDispatcher         │
        │  (Route by NSID)        │
        └────────┬────────────────┘
                 │
        ┌────────▼────────────────┐
        │  XrpcMethodRegistry     │
        │  (Method handlers)      │
        └────────┬────────────────┘
                 │
        ┌────────▼────────────────┐
        │  PDSApplication         │
        │  (Services & DB)        │
        └─────────────────────────┘
```

## References

- [Tutorial 1: Hello PDS](../../docs/10-tutorials/tutorial-1-hello-pds.md)
- [Architecture Overview](../../docs/01-getting-started/architecture-overview.md)
- [HTTP Server Documentation](../../docs/04-network-layer/http-server.md)

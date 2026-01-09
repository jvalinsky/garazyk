# Setup and Installation Guide

This guide covers building, installing, and running the ATProto PDS server.

## Prerequisites

### System Requirements

- **macOS**: 12.0 or later (Monterey, Ventura, Sonoma)
- **Xcode**: 15.0 or later
- **Command Line Tools**: Latest version
- **Disk Space**: ~2GB for build artifacts and dependencies

### Hardware Recommendations

- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 10GB free space
- **Network**: Stable internet connection (for external API calls)

## Installation Methods

### Method 1: Quick Setup (Recommended)

```bash
# Clone repository
git clone https://github.com/jvalinsky/NSPds.git
cd NSPds

# Build and run
make build
./scripts/start_server.sh
```

Server will be available at `http://localhost:2583`

### Method 2: Development Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/jvalinsky/NSPds.git
cd NSPds

# Install dependencies
make deps

# Build debug version
make build-debug

# Run with verbose logging
./build/debug/atprotopds-cli serve --port 2583 --verbose
```

### Method 3: Xcode Development

```bash
# Open in Xcode
open ATProtoPDS.xcodeproj

# Select scheme: ATProtoPDS-CLI
# Build and run
```

## Build System

### Available Targets

```bash
# Using Make
make build          # Build all targets
make build-cli      # Command-line server only
make build-gui      # macOS GUI application
make build-release  # Optimized release build

# Using Xcode
xcodebuild -project ATProtoPDS.xcodeproj -scheme ATProtoPDS-CLI build
xcodebuild -project ATProtoPDS.xcodeproj -scheme ATProtoPDS build
```

### Build Configuration

#### Debug Build
```bash
make build-debug
# Features: Logging, assertions, debug symbols
# Size: Larger binary
# Performance: Slower but detailed error info
```

#### Release Build
```bash
make build-release
# Features: Optimized, stripped symbols
# Size: Smaller binary
# Performance: Faster, production-ready
```

## Dependencies

### Required Libraries

The project automatically handles most dependencies:

- **SQLite**: Database engine (included)
- **OpenSSL**: Cryptography (via macOS)
- **libsecp256k1**: ECDSA operations (submodule)
- **Foundation**: macOS frameworks (system)

### Manual Dependency Installation

If automatic setup fails:

```bash
# Install Homebrew (if not present)
# https://brew.sh/

/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Install required tools
brew install sqlite openssl

# Update submodules
git submodule update --init --recursive
```

## Configuration

### Server Configuration

Create `config.json` in the project root:

```json
{
  "port": 2583,
  "dataDirectory": "./data",
  "cacheDirectory": "./cache",
  "logLevel": "info",
  "enableCors": true,
  "trustedOrigins": ["http://localhost:3000"]
}
```

### Environment Variables

```bash
# Set data directory
export AT_PROTO_DATA_DIR="./data"

# Set cache directory
export AT_PROTO_CACHE_DIR="./cache"

# Enable debug logging
export AT_PROTO_LOG_LEVEL="debug"

# Set server port
export AT_PROTO_PORT="2583"
```

### Database Configuration

The server automatically creates and migrates the SQLite database. To reset:

```bash
# Stop server
pkill -f "atprotopds"

# Remove database
rm -f data/pds.db

# Restart server (will recreate database)
./scripts/start_server.sh
```

## Running the Server

### Basic Startup

```bash
# Using script
./scripts/start_server.sh

# Manual startup
./build/release/atprotopds-cli serve --port 2583

# Background process
nohup ./scripts/start_server.sh &
```

### Command Line Options

```bash
./atprotopds-cli serve --help

Options:
  --port PORT          Server port (default: 2583)
  --data-dir PATH      Data directory (default: ./data)
  --cache-dir PATH     Cache directory (default: ./cache)
  --log-level LEVEL    Log level: error, warn, info, debug
  --verbose           Enable verbose logging
  --help              Show this help
```

### Systemd Service (Optional)

For production deployment, create a systemd service:

```bash
# Create service file
sudo tee /etc/systemd/system/atproto-pds.service > /dev/null <<EOF
[Unit]
Description=ATProto PDS Server
After=network.target

[Service]
Type=simple
User=atproto
WorkingDirectory=/opt/atproto-pds
ExecStart=/opt/atproto-pds/atprotopds-cli serve --port 2583
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl enable atproto-pds
sudo systemctl start atproto-pds
```

## Verification

### Health Checks

```bash
# Check if server is running
curl -s http://localhost:2583/explore/api/accounts | head -5

# Check database connection
curl -s "http://localhost:2583/explore/api/debug" | jq .dbExists

# Test API endpoints
./scripts/test_endpoints.sh
```

### Log Files

```bash
# View server logs
tail -f server.log

# Check for errors
grep "ERROR\|error" server.log

# Monitor API requests
tail -f server.log | grep "handleApi"
```

### Browser Testing

1. **Explorer UI**: `http://localhost:2583/explore/`
2. **API Documentation**: `http://localhost:2583/explore/api/docs`
3. **OpenAPI Spec**: `http://localhost:2583/explore/api/openapi.yaml`

## Troubleshooting Installation

### Build Failures

#### Xcode Version Issues
```bash
# Check Xcode version
xcodebuild -version

# Select Xcode version
sudo xcode-select -s /Applications/Xcode.app

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/ATProtoPDS-*
```

#### Missing Dependencies
```bash
# Reinstall dependencies
make clean-deps
make deps

# Check library paths
otool -L build/debug/atprotopds-cli
```

#### Compilation Errors
```bash
# Clean and rebuild
make clean
make build

# Check for syntax errors
xcodebuild -project ATProtoPDS.xcodeproj -scheme ATProtoPDS-CLI clean build 2>&1 | head -50
```

### Runtime Issues

#### Port Already in Use
```bash
# Find process using port
lsof -i :2583

# Kill process
kill -9 <PID>

# Or use different port
./atprotopds-cli serve --port 2584
```

#### Database Permission Issues
```bash
# Fix permissions
chmod 755 data/
chmod 644 data/pds.db

# Reset database
rm -f data/pds.db
./scripts/start_server.sh
```

#### Memory Issues
```bash
# Check memory usage
ps aux | grep atprotopds

# Monitor with Activity Monitor
# Look for memory leaks or excessive usage
```

### Network Issues

#### Firewall Blocking
```bash
# Check if port is accessible
telnet localhost 2583

# Disable firewall temporarily for testing
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
```

#### DNS Resolution
```bash
# Test external API connectivity
curl -s https://plc.directory/did:plc:g3x5vnga7kiu3oaookgeozpb | head -5

# Check DNS resolution
nslookup plc.directory
```

## Performance Tuning

### Memory Configuration

```bash
# Increase cache sizes (in config.json)
{
  "memoryCacheSize": 100,
  "diskCacheSize": "500MB"
}
```

### Database Optimization

```bash
# Enable WAL mode
sqlite3 data/pds.db "PRAGMA journal_mode=WAL;"

# Optimize database
sqlite3 data/pds.db "VACUUM; ANALYZE;"
```

### Network Tuning

```bash
# Adjust timeouts (in config.json)
{
  "requestTimeout": 30,
  "externalApiTimeout": 10
}
```

## Development Setup

### IDE Configuration

#### Xcode
1. Open `ATProtoPDS.xcodeproj`
2. Select `ATProtoPDS-CLI` scheme
3. Set build configuration to `Debug`
4. Add breakpoints as needed

#### VS Code
```json
{
  "ccls.clang.extraArgs": [
    "-I${workspaceFolder}/ATProtoPDS/Sources",
    "-F/Library/Frameworks"
  ]
}
```

### Testing

```bash
# Run unit tests
make test

# Run integration tests
./scripts/test_server.sh

# Run security tests
make security-test
```

### Debugging

```bash
# Enable verbose logging
./atprotopds-cli serve --verbose --log-level debug

# Attach debugger
lldb ./atprotopds-cli
(lldb) run serve --port 2583

# Check core dumps
ls /cores/
```

## Deployment

### Production Deployment

1. **Build release version**
   ```bash
   make build-release
   ```

2. **Configure environment**
   ```bash
   export AT_PROTO_PORT=80
   export AT_PROTO_DATA_DIR=/var/lib/atproto
   ```

3. **Set up reverse proxy** (nginx example)
   ```nginx
   server {
       listen 80;
       server_name your-domain.com;

       location / {
           proxy_pass http://localhost:2583;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
       }
   }
   ```

4. **Enable SSL** with Let's Encrypt
   ```bash
   certbot --nginx -d your-domain.com
   ```

### Docker Deployment (Future)

```dockerfile
FROM macos:latest
COPY . /app
RUN make build-release
EXPOSE 2583
CMD ["/app/atprotopds-cli", "serve", "--port", "2583"]
```

## Support

### Getting Help

1. **Check documentation**: See `docs/` folder
2. **View logs**: `tail -f server.log`
3. **Test endpoints**: `./scripts/test_endpoints.sh`
4. **GitHub Issues**: Report bugs and request features

### Common Support Questions

- **"Server won't start"**: Check port availability and logs
- **"Database errors"**: Reset database or check permissions
- **"Slow performance"**: Clear cache or check network connectivity
- **"API errors"**: Verify request format and check server logs

### Community Resources

- **Documentation**: `docs/` folder in repository
- **API Reference**: `http://localhost:2583/explore/api/docs`
- **Architecture**: `docs/ARCHITECTURE_DIAGRAMS.md`
- **Implementation**: `docs/SESSION_SUMMARY.md`
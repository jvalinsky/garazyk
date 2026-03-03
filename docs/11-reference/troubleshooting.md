# Troubleshooting Guide

## Common Issues and Solutions

### Build Issues

#### CMake Configuration Fails

**Problem:** `cmake ..` fails with configuration errors

**Solution:**
```bash
# 1. Clean build directory
rm -rf build
mkdir build && cd build

# 2. Verify dependencies
brew list | grep -E "cmake|openssl|sqlite"

# 3. Specify paths if needed
cmake .. -DOPENSSL_DIR=/usr/local/opt/openssl -DSQLITE3_DIR=/usr/local/opt/sqlite

# 4. Check CMakeLists.txt for required versions
cat ../CMakeLists.txt | grep -E "cmake_minimum_required|find_package"
```

#### Xcode Build Fails

**Problem:** `xcodebuild` fails with compilation errors

**Solution:**
```bash
# 1. Regenerate Xcode project
xcodegen generate

# 2. Clean build
xcodebuild clean -scheme ATProtoPDS-CLI

# 3. Build with verbose output
xcodebuild -scheme ATProtoPDS-CLI build -verbose

# 4. Check for missing dependencies
xcodebuild -scheme ATProtoPDS-CLI build -showBuildSettings | grep -E "HEADER_SEARCH_PATHS|LIBRARY_SEARCH_PATHS"
```

#### GNUstep Build Fails

**Problem:** Linux/GNUstep build fails

**Solution:**
```bash
# 1. Install GNUstep development files
sudo apt-get install gnustep-devel

# 2. Source GNUstep environment
source /usr/share/GNUstep/Makefiles/GNUstep.sh

# 3. Clean and rebuild
rm -rf build-linux
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)

# 4. Check for missing libraries
ldd ./bin/kaszlak | grep "not found"
```

### Runtime Issues

#### Server Won't Start

**Problem:** `kaszlak` starts but immediately exits

**Solution:**
```bash
# 1. Check configuration file
cat config.json | jq .

# 2. Verify port is available
lsof -i :2583

# 3. Run with verbose logging
./build/bin/kaszlak --verbose --config config.json

# 4. Check data directory permissions
ls -la data/

# 5. Verify database integrity
sqlite3 data/service.db "PRAGMA integrity_check;"
```

#### Port Already in Use

**Problem:** "Address already in use" error

**Solution:**
```bash
# 1. Find process using port
lsof -i :2583

# 2. Kill existing process
kill -9 <PID>

# 3. Or use different port
./build/bin/kaszlak --config config.json --port 2584

# 4. Check for zombie processes
ps aux | grep kaszlak
```

#### Database Locked

**Problem:** "Database is locked" error

**Solution:**
```bash
# 1. Check for open connections
sqlite3 data/service.db "PRAGMA database_list;"

# 2. Verify WAL mode is enabled
sqlite3 data/service.db "PRAGMA journal_mode;"

# 3. Remove WAL files if corrupted
rm -f data/service.db-wal data/service.db-shm

# 4. Rebuild database
sqlite3 data/service.db ".dump" > backup.sql
rm data/service.db
sqlite3 data/service.db < backup.sql
```

### Network Issues

#### Connection Refused

**Problem:** Client can't connect to PDS

**Solution:**
```bash
# 1. Verify server is running
ps aux | grep kaszlak

# 2. Check if port is listening
netstat -tlnp | grep 2583

# 3. Test local connection
curl -v http://localhost:2583/xrpc/com.atproto.server.describeServer

# 4. Check firewall rules
sudo iptables -L -n | grep 2583

# 5. Verify configuration
cat config.json | jq .server
```

#### TLS Certificate Errors

**Problem:** "Certificate verification failed" error

**Solution:**
```bash
# 1. Check certificate validity
openssl x509 -in cert.pem -text -noout

# 2. Verify certificate chain
openssl verify -CAfile ca.pem cert.pem

# 3. Check certificate dates
openssl x509 -in cert.pem -noout -dates

# 4. Regenerate self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# 5. Update configuration
cat config.json | jq '.server.tls = {cert: "cert.pem", key: "key.pem"}'
```

#### WebSocket Connection Fails

**Problem:** WebSocket upgrade fails

**Solution:**
```bash
# 1. Check WebSocket endpoint
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  http://localhost:2583/xrpc/com.atproto.sync.subscribeRepos

# 2. Verify headers
curl -v http://localhost:2583/xrpc/com.atproto.sync.subscribeRepos 2>&1 | grep -i upgrade

# 3. Check for proxy issues
# WebSocket may fail behind certain proxies
# Verify nginx/reverse proxy configuration

# 4. Test with wscat
npm install -g wscat
wscat -c ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos
```

### Authentication Issues

#### JWT Token Invalid

**Problem:** "Invalid JWT token" error

**Solution:**
```bash
# 1. Verify token format
echo $TOKEN | cut -d'.' -f1 | base64 -d | jq .

# 2. Check token expiration
echo $TOKEN | cut -d'.' -f2 | base64 -d | jq .exp

# 3. Verify signature
# Use JWT.io or similar tool to verify

# 4. Check clock skew
date -u

# 5. Regenerate token
curl -X POST http://localhost:2583/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{"identifier":"user@example.com","password":"password"}'
```

#### DPoP Proof Invalid

**Problem:** "Invalid DPoP proof" error

**Solution:**
```bash
# 1. Verify DPoP header format
curl -v -H "DPoP: <proof>" http://localhost:2583/xrpc/com.atproto.server.getSession

# 2. Check proof timestamp
# DPoP proof must be recent (within 60 seconds)

# 3. Verify proof signature
# Proof must be signed with correct key

# 4. Check method/URI match
# DPoP proof must match HTTP method and URI

# 5. Regenerate proof
# Create new DPoP proof with current timestamp
```

#### OAuth Flow Fails

**Problem:** OAuth authorization fails

**Solution:**
```bash
# 1. Verify OAuth configuration
cat config.json | jq '.oauth'

# 2. Check redirect URI
# Must match registered URI exactly

# 3. Verify authorization code
# Code must be used within 10 minutes

# 4. Check client credentials
# Client ID and secret must be correct

# 5. Test OAuth flow manually
curl -X POST http://localhost:2583/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&code=<code>&client_id=<id>&client_secret=<secret>"
```

### Performance Issues

#### High Memory Usage

**Problem:** PDS process uses excessive memory

**Solution:**
```bash
# 1. Monitor memory usage
watch -n 1 'ps aux | grep kaszlak'

# 2. Check for memory leaks
valgrind --leak-check=full ./build/bin/kaszlak

# 3. Reduce buffer sizes
cat config.json | jq '.network.maxBufferSize = 5242880'

# 4. Clear caches
# Restart PDS to clear in-memory caches

# 5. Check database size
du -sh data/

# 6. Vacuum database
sqlite3 data/service.db "VACUUM;"
```

#### Slow Response Times

**Problem:** API responses are slow

**Solution:**
```bash
# 1. Check database performance
sqlite3 data/service.db "EXPLAIN QUERY PLAN SELECT * FROM records WHERE did = 'did:plc:...';"

# 2. Verify indexes exist
sqlite3 data/service.db ".indices"

# 3. Check query execution time
sqlite3 data/service.db ".timer on"
sqlite3 data/service.db "SELECT COUNT(*) FROM records;"

# 4. Monitor CPU usage
top -p <PID>

# 5. Check for lock contention
sqlite3 data/service.db "PRAGMA busy_timeout = 5000;"

# 6. Enable query logging
cat config.json | jq '.debug.logQueries = true'
```

#### High CPU Usage

**Problem:** PDS process uses excessive CPU

**Solution:**
```bash
# 1. Profile CPU usage
perf record -p <PID> -g -- sleep 10
perf report

# 2. Check for busy loops
# Look for functions with high CPU time

# 3. Reduce polling frequency
cat config.json | jq '.polling.interval = 5000'

# 4. Check for excessive logging
cat config.json | jq '.debug.logLevel = "warn"'

# 5. Monitor thread count
ps -eLf | grep kaszlak | wc -l

# 6. Check for thread contention
# Use thread profiler to identify bottlenecks
```

### Data Issues

#### Corrupted Database

**Problem:** Database integrity check fails

**Solution:**
```bash
# 1. Check integrity
sqlite3 data/service.db "PRAGMA integrity_check;"

# 2. Backup current database
cp data/service.db data/service.db.backup

# 3. Attempt repair
sqlite3 data/service.db "PRAGMA integrity_check(1000);"

# 4. Rebuild database
sqlite3 data/service.db ".dump" > backup.sql
rm data/service.db
sqlite3 data/service.db < backup.sql

# 5. Verify repair
sqlite3 data/service.db "PRAGMA integrity_check;"

# 6. Restart PDS
./build/bin/kaszlak --config config.json
```

#### Missing Records

**Problem:** Records are missing from database

**Solution:**
```bash
# 1. Check record count
sqlite3 data/service.db "SELECT COUNT(*) FROM records;"

# 2. Verify record exists
sqlite3 data/service.db "SELECT * FROM records WHERE uri = 'at://...';"

# 3. Check deletion log
sqlite3 data/service.db "SELECT * FROM deleted_records WHERE uri = 'at://...';"

# 4. Restore from backup
# If backup available, restore and re-sync

# 5. Re-sync repository
curl -X POST http://localhost:2583/xrpc/com.atproto.sync.getRepo \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"did":"did:plc:..."}'
```

#### Inconsistent State

**Problem:** Repository state is inconsistent

**Solution:**
```bash
# 1. Verify MST root
sqlite3 data/service.db "SELECT root_cid FROM repositories WHERE did = 'did:plc:...';"

# 2. Check commit history
sqlite3 data/service.db "SELECT * FROM commits WHERE did = 'did:plc:...' ORDER BY seq DESC LIMIT 10;"

# 3. Rebuild MST
# Requires re-syncing repository

# 4. Verify record signatures
# Check that all records are properly signed

# 5. Re-sync from PLC
# Force re-sync with PLC directory
```

### Testing Issues

#### Tests Fail to Build

**Problem:** Test compilation fails

**Solution:**
```bash
# 1. Clean test build
xcodebuild clean -scheme AllTests

# 2. Rebuild tests
xcodebuild -scheme AllTests build

# 3. Check for missing test files
find ATProtoPDS/Tests -name "*.m" | wc -l

# 4. Verify test class registration
grep "testClasses" ATProtoPDS/Tests/test_main.m

# 5. Add missing test class
# Edit test_main.m and add class to testClasses array
```

#### Tests Fail to Run

**Problem:** Tests compile but fail to execute

**Solution:**
```bash
# 1. Run tests with verbose output
./build/tests/AllTests -v

# 2. Run specific test class
./build/tests/AllTests -XCTest MSTInteropTests

# 3. Check for missing dependencies
ldd ./build/tests/AllTests | grep "not found"

# 4. Verify test data files
ls -la ATProtoPDS/Tests/fixtures/

# 5. Check test permissions
chmod +x ./build/tests/AllTests
```

#### Flaky Tests

**Problem:** Tests pass sometimes, fail other times

**Solution:**
```bash
# 1. Run tests multiple times
for i in {1..10}; do ./build/tests/AllTests -XCTest TestName || break; done

# 2. Check for timing issues
# Add delays or use proper synchronization

# 3. Check for shared state
# Ensure tests don't depend on execution order

# 4. Verify test isolation
# Each test should be independent

# 5. Check for race conditions
# Use thread sanitizer
clang -fsanitize=thread -g ./build/tests/AllTests
```

## Debugging Techniques

### Enable Debug Logging

```bash
# Set environment variables
export PDS_DEBUG=1
export PDS_LOG_LEVEL=debug

# Run with verbose output
./build/bin/kaszlak --verbose --config config.json

# Check logs
tail -f logs/pds.log
```

### Use Debugger

```bash
# macOS: lldb
lldb ./build/bin/kaszlak
(lldb) run --config config.json
(lldb) breakpoint set -n main
(lldb) continue

# Linux: gdb
gdb ./build/bin/kaszlak
(gdb) run --config config.json
(gdb) break main
(gdb) continue
```

### Inspect Database

```bash
# Open database
sqlite3 data/service.db

# List tables
.tables

# Inspect schema
.schema records

# Query data
SELECT * FROM records LIMIT 10;

# Export data
.output dump.sql
.dump
.output stdout
```

## Getting Help

### Check Logs

```bash
# View recent logs
tail -100 logs/pds.log

# Search for errors
grep -i error logs/pds.log

# Check specific time range
grep "2024-01-01" logs/pds.log
```

### Collect Diagnostics

```bash
# Create diagnostic bundle
mkdir diagnostics
cp config.json diagnostics/
cp logs/pds.log diagnostics/
sqlite3 data/service.db ".dump" > diagnostics/database.sql
ps aux | grep kaszlak > diagnostics/processes.txt
netstat -tlnp > diagnostics/network.txt
df -h > diagnostics/disk.txt

# Compress for sharing
tar -czf diagnostics.tar.gz diagnostics/
```

### Report Issues

When reporting issues, include:
1. PDS version
2. Platform (macOS/Linux)
3. Configuration (sanitized)
4. Error logs
5. Steps to reproduce
6. Expected vs actual behavior

## Performance Tuning

### Database Optimization

```bash
# Enable query optimization
sqlite3 data/service.db "PRAGMA optimize;"

# Analyze query plans
sqlite3 data/service.db "ANALYZE;"

# Rebuild indexes
sqlite3 data/service.db "REINDEX;"

# Vacuum database
sqlite3 data/service.db "VACUUM;"
```

### Network Optimization

```bash
# Increase buffer sizes
cat config.json | jq '.network.maxBufferSize = 52428800'

# Enable compression
cat config.json | jq '.network.compression = true'

# Tune TCP settings
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
```

### Memory Optimization

```bash
# Reduce cache size
cat config.json | jq '.cache.maxSize = 104857600'

# Enable memory pooling
cat config.json | jq '.memory.pooling = true'

# Monitor memory usage
watch -n 1 'ps aux | grep kaszlak | grep -v grep'
```

## Next Steps

- **[CLI Reference](./cli-reference.md)** — Command-line interface
- **[Config Reference](./config-reference.md)** — Configuration options
- **[API Reference](./api-reference.md)** — XRPC endpoints


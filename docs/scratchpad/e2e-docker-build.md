# Docker E2E - Build Images

## Node 91

**Status**: Pending

## Tasks
- [ ] Build nspds:local Docker image
- [ ] Verify PLC replica runs
- [ ] Verify PDS runs
- [ ] Verify Relay runs

## Notes

### Build Command
```bash
docker build -f docker/Dockerfile.gnustep -t nspds:local .
```

### Image Tag
- nspds:local

### Verification
- PLC: `curl http://localhost:2580/xrpc/_health`
- PDS: `curl http://localhost:2583/xrpc/com.atproto.server.describeServer`
- Relay: `curl http://localhost:2584/xrpc/com.atproto.sync.getHead?repo=did:plc:test`

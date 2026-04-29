# Docker E2E - Docker Compose and Configs

## Node 90

**Status**: Pending

## Tasks
- [ ] Create docker/e2e/docker-compose.yml
- [ ] Create docker/e2e/plc-config.json
- [ ] Create docker/e2e/pds-config.json  
- [ ] Create docker/e2e/relay-config.json

## Notes

### Service Ports
- PLC Replica: 2580
- PDS: 2583
- Relay: 2584

### Network
- e2e_network (bridge)

### Dependencies
- PLC must start first
- PDS waits for PLC
- Relay waits for PDS

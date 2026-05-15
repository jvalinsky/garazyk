---
title: Chat Service (PDS2)
---

# Chat Service (PDS2)

Garazyk supports a secondary PDS instance, referred to as **PDS2** or the **Chat Service**, primarily used for testing federation and multi-PDS interactions.

## Overview

While a single Garazyk PDS is functional for local development, certain AT Protocol features require a multi-node environment to verify:

- **Cross-PDS Synchronization**: Validating data propagation between independent authorities.
- **Account Migration**: Testing the transfer of user repositories between servers.
- **Multi-Tenant Federation**: Simulating interactions across the broader network.

PDS2 is a standard instance of the Garazyk binary, configured with a distinct identity and isolated storage to act as a peer node.

## Configuration

In the local developer environment (orchestrated by `scripts/reseed_local_network.sh`), PDS2 is configured with its own ports and data directories:

| Parameter | Primary PDS | PDS2 (Chat) |
| --- | --- | --- |
| **HTTP Port** | 2583 | 2585 |
| **Master Secret** | `test-master-secret-123` | `test-master-secret-456` |
| **Data Directory** | `./data/pds` | `./data/pds2` |
| **PLC Keys** | `./data/pds/keys` | `./data/pds2/keys` |

## Role in Scenarios

PDS2 provides a second authority for end-to-end testing:

- **Federation (Scenario 05)**: Verifies that a record created on PDS1 is indexed by the Relay and AppView, and remains reachable by an agent authenticated against PDS2.
- **Account Migration (Scenario 12)**: Exercises the migration of a user repository from PDS1 to PDS2, including PLC rotation key updates and MST synchronization.

## Execution

PDS2 is disabled by default to conserve resources. It can be started via the CLI or the scenario dashboard:

### CLI (Deno)
```bash
./scripts/run_scenarios.ts --pds2 [scenario_ids]
```

### Scenario Dashboard
Use the **"Start with PDS2"** toggle in the Network Status panel.

## Implementation Details

PDS2 runs the same code and XRPC method packs as the primary PDS. It is "Chat-focused" only in the sense that it serves as the destination for messaging tests in the narrative scenario suite.

## Related

- [Services Overview](./services-overview)
- [PDS Application Facade](./pds-application)
- [Relay Server](./relay-server)
- [AppView Server](./appview-server)
- [Testing ATProto Federation](../07-repository-protocol/testing-atproto-federation)
- [Scenario Testing Guide](../docs/tests/scenario-testing.md)

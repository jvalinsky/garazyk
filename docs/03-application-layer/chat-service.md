---
title: Chat Service (PDS2)
---

# Chat Service (PDS2)

Garazyk supports a secondary PDS instance, referred to as **PDS2** or the **Chat Service**, used for testing federation and multi-PDS interactions.

## Overview

While a single Garazyk PDS is functional, certain AT Protocol features—such as cross-PDS data synchronization, account migration, and multi-tenant federation—require a second node during testing.

PDS2 is an instance of the Garazyk binary, configured with a distinct identity and isolated storage.

## Configuration

In the local developer environment (orchestrated by `scripts/scenarios/setup_local_network.sh`), PDS2 is configured with the following characteristics:

| Parameter | Primary PDS | PDS2 (Chat) |
| --- | --- | --- |
| **HTTP Port** | 2583 | 2585 |
| **Master Secret** | `test-master-secret-123` | `test-master-secret-456` |
| **Data Directory** | `./data/pds` | `./data/pds2` |
| **PLC Keys** | `./data/pds/keys` | `./data/pds2/keys` |

## Usage in Scenarios

PDS2 is used in scenarios that require two distinct authorities. For example:

*   **Scenario 05 (Federation)**: Validates that a record created on PDS1 is successfully indexed by the Relay and AppView, and is reachable by an agent authenticated against PDS2.
*   **Scenario 12 (Account Migration)**: Exercises the migration of a user repository from PDS1 to PDS2, including PLC rotation key updates and synchronization of the Merkle Search Tree (MST).

## Enabling PDS2

PDS2 is not started by default to save resources. To enable it:

### CLI (Deno)
```bash
./scripts/run_scenarios.ts --pds2 [scenario_ids]
```

### Scenario Dashboard
Click the **"Start with PDS2"** button in the Network Status panel.

## Implementation Details

PDS2 runs the same XRPC method packs as the primary PDS. It is "Chat-focused" only in the sense that it serves as the destination for E2E messaging tests in the narrative scenario suite. It does not contain a different codebase from the main PDS.

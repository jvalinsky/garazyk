# Services Overview

The service layer translates protocol requests into application logic. `PDSApplication` is the composition root, managing infrastructure, core services, and route wiring.

## Architecture

Garazyk separates concerns into three layers:
- **Handlers**: Parse requests and shape responses.
- **Services**: Coordinate business logic and subsystem interactions.
- **Persistence**: Manage database and repository state.

## Service Composition

`PDSApplication` initializes shared infrastructure:
- Configuration and logging.
- Rate limiting and JWT infrastructure.
- Service databases and the actor database pool.

It then assembles the application services:
- **Account Service**: Manages accounts and authentication.
- **Record Service**: Handles record CRUD.
- **Blob Service**: Manages binary data and storage.
- **Repository Service**: Oversees MST and repository integrity.
- **Admin/Safety Services**: Age assurance, chat moderation, and administrative controls.
- **Relay Service**: Handles firehose and notification propagation.

### Standalone Servers
Garazyk implements standalone servers for specialized protocol roles:
- **Syrena (AppView)**: Consumes the firehose to build read-models.
- **Zuk (Relay)**: Aggregates data from multiple PDS instances.
- **Campagnola (PLC)**: Implements the `did:plc` directory server.

## Request Execution Flow
1. **Routing**: Matches the request in the HTTP builder or XRPC layer.
2. **Pre-processing**: Auth and validation run in middleware or helpers.
3. **Coordination**: The handler calls the relevant domain service.
4. **Persistence**: The service executes repository or database operations.
5. **Response**: The handler shapes the final payload.

## Implementation Guidelines

### PDSController
`PDSController` is a legacy facade. New implementation should target services directly.

### Service Boundaries
Add or extend services for logic that:
- Spans multiple handlers or protocol namespaces.
- Coordinates multiple persistence layers.
- Requires a testable boundary independent of transport.

Services must represent a meaningful architectural seam. Trivial logic remains in handlers or helpers.

## Related

- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Runtime Flow Walkthrough](./runtime-flow-walkthrough)
- [Syrena AppView](./appview-server)
- [Zuk Relay](./relay-server)
- [Safety and Compliance](./safety-and-compliance)
- [Blob Service](./blob-service)
- [Repository Service](./repository-service)
- [Documentation Map](../11-reference/documentation-map.md)


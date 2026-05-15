# Services Overview

The service layer translates protocol requests into application logic. [PDSApplication](./pds-application) acts as the composition root, coordinating infrastructure, domain services, and route dispatch.

## Architectural Layers

Garazyk separates concerns into three distinct layers:
- **Handlers**: Parse requests and shape responses (see [XRPC Dispatch](../04-network-layer/xrpc-dispatch)).
- **Services**: Coordinate business logic and subsystem interactions.
- **Persistence**: Manage database state and repository integrity.

## Application Services

`PDSApplication` initializes the core application services:

- **[Account Service](./account-service)**: Manages user accounts, authentication, and session lifecycles.
- **[Record Service](./record-service)**: Handles record creation, retrieval, and validation.
- **[Blob Service](./blob-service)**: Manages binary data storage and AT Protocol blob objects.
- **[Repository Service](./repository-service)**: Oversees [MST reconstruction](../02-core-concepts/mst-trees) and repository exports.
- **[Admin](./admin-service) & [Safety](./safety-and-compliance) Services**: Manage age assurance, chat moderation, and administrative controls.
- **[Relay Service](./relay-service)**: Handles outbound notification propagation for the [firehose](../08-sync-firehose/firehose-overview).

## Standalone Servers

In addition to the PDS, the codebase supports specialized protocol roles:
- **Syrena ([AppView](./appview-server))**: Consumes the firehose to build specialized read-models.
- **Zuk ([Relay](./relay-server))**: Aggregates data from multiple PDS instances for indexing.
- **Campagnola (PLC)**: Implements the [PLC](../GLOSSARY.md#plc) directory server.

## Request Execution Flow

A typical request follows this sequence:
1. **Routing**: The [HTTP Server](../04-network-layer/http-server) or [XRPC Dispatch](../04-network-layer/xrpc-dispatch) layer matches the request.
2. **Pre-processing**: [Auth Helpers](../04-network-layer/auth-helpers) and [Input Validation](../04-network-layer/input-validation) run before service logic.
3. **Coordination**: The handler invokes the relevant domain service.
4. **Persistence**: The service executes repository or database operations.
5. **Response**: The handler shapes the final payload for the client.

## Implementation Standards

### Service Boundaries
Extend or create services for logic that:
- Spans multiple handlers or protocol namespaces.
- Coordinates multiple persistence layers (e.g., database and MST).
- Requires a testable boundary independent of the HTTP transport.

### Legacy Facade
`PDSController` is a legacy interface maintained for compatibility. New features should target the domain services directly.

## Related

- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Runtime Flow Walkthrough](./runtime-flow-walkthrough)
- [PDS Application Facade](./pds-application)
- [HTTP Server](../04-network-layer/http-server)
- [XRPC Dispatch](../04-network-layer/xrpc-dispatch)
- [Documentation Map](../11-reference/documentation-map.md)


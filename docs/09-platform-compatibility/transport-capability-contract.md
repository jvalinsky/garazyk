# Transport Capability Contract

This document defines the portability expectations for `PDSNetworkTransport` implementations across all supported platforms.

## Required Capabilities

To ensure the `HttpServer` behaves consistently, all transport drivers must meet these criteria:

- **State Transitions**: Terminal states must be `Failed` or `Cancelled`. Once a connection reaches a terminal state, it must not regress to an active state.
- **Completion Ordering**: Each `sendData:completion:` call must eventually trigger its completion handler exactly once, either on success or failure.
- **Delivery Semantics**: When a connection reaches EOF, any remaining buffered bytes must be delivered with the `isComplete` flag set to `YES`.
- **Address Stability**: The `remoteAddress` property must remain stable and non-empty for the entire lifetime of the connection.
- **Host Binding**: Attempts to bind to an invalid or unavailable host must fail explicitly rather than silently broadening to all interfaces.
- **Port Reporting**: Ephemeral ports must only be reported once the listener has entered the `Ready` state.

## Platform-Specific Behavior

- **macOS**: May emit transitional states like `Waiting` or `Preparing` before reaching `Ready`.
- **Linux**: May collapse these transitional states but must preserve the terminal state semantics.
- **Address Formatting**: Callers should treat the `remoteAddress` string as an opaque identifier for logging and rate limiting, rather than assuming a specific IPv4/IPv6 format.

## Shim Policy

`GNUstepCFNetworkCompat.h` serves as an alias to the canonical shim located in `Compat/PlatformShims/CoreFoundation/CFNetwork`. Do not add local no-op CFHTTP stubs that silently return `nil` or `NO`, as this can mask configuration errors.

## Related
- [Network Transport](./network-transport)
- [macOS vs GNUstep Boundary](./macos-vs-gnustep-boundary)
- [Compatibility Layer](./compatibility-layer)

# Transport Capability Contract

This document defines portability expectations for `PDSNetworkTransport`.

## Required capabilities

- `conn.state_machine`: terminal states are `Failed` and `Cancelled`; no state regressions.
- `conn.send_completion_ordering`: each `sendData:completion:` invocation must complete or fail explicitly.
- `conn.receive_delivery_semantics`: EOF with buffered bytes returns bytes with `isComplete=YES`.
- `conn.remote_address_format`: `remoteAddress` is stable and non-empty for connection lifetime.
- `listener.bind_host_strictness`: invalid explicit hosts must fail rather than silently broadening to all interfaces.
- `listener.port_binding_policy`: ephemeral ports are reported only after ready state.

## Platform notes

- macOS may emit additional transitional states (`Waiting`, `Preparing`).
- Linux/GNUstep may collapse transitional states but must preserve terminal semantics.
- Callers must treat `remoteAddress` as an opaque identifier, not parse strict structure.

## Shim policy

`GNUstepCFNetworkCompat.h` is an alias to the canonical shim in
`Compat/PlatformShims/CoreFoundation/CFNetwork.*`. Do not add local no-op
CFHTTP stubs that silently return `nil`/`NO`.

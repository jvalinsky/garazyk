# Issue: Linux transport client path unimplemented

## Summary
`ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m` currently short-circuits with `Client connection not implemented` whenever `_sockfd` is `-1`, which is the code path used for client-side connections.

## Impact
- Linux builds cannot initiate outbound PDS connections, preventing the target from participating in peer-to-peer communication.
- The client transport reports an error before any network work takes place, so higher-level features that rely on client sockets cannot succeed.

## Proposed fix
- Implement the client connect loop, including DNS/socket creation, async read/write handling, and readiness notifications.
- Ensure the state machine transitions to `PDSNetworkConnectionStateReady` once the socket is connected and sources are set up.
- Consider reusing the existing `setupSources` logic to attach dispatch sources even for client sockets.

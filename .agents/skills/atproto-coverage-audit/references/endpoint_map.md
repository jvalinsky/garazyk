# Endpoint Map Notes

- XRPC registration lives in `Garazyk/Sources/Network/XrpcMethodRegistry.m`.
- Primary handler implementations are in:
  - `Garazyk/Sources/App/PDSController.m`
  - `Garazyk/Sources/AppView/`
  - `Garazyk/Sources/Sync/SubscribeReposHandler.m`
  - `Garazyk/Sources/Network/`
- Use the registry list to map method IDs to handler blocks.

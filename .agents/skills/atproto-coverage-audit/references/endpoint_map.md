# Endpoint Map Notes

- XRPC registration lives in `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`.
- Primary handler implementations are in:
  - `ATProtoPDS/Sources/App/PDSController.m`
  - `ATProtoPDS/Sources/AppView/`
  - `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m`
  - `ATProtoPDS/Sources/Network/`
- Use the registry list to map method IDs to handler blocks.

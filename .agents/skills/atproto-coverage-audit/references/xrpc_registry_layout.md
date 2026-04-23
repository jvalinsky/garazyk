# XRPC Registry Layout

- Method registrations live in `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m`.
- Each `register*` call maps an XRPC method to a handler block.
- Use the registry list to find handler ownership and responses.

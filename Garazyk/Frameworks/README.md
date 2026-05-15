# ATProto Framework-Style Modules (Experimental v0)

This directory defines umbrella headers for boundary-first modularization.

Dependency direction (high-level):

1. `ATProtoCore`
2. `ATProtoStorage`, `ATProtoTransport`
3. `ATProtoServices`, `ATProtoSync`, `ATProtoPLC`
4. `ATProtoXRPC`
5. `ATProtoRuntime`

These APIs are marked experimental (`v0`) and may evolve while module extraction
continues.

Umbrella ownership rules:

- `ATProtoTransport` exports transport/runtime-agnostic HTTP primitives only.
- `ATProtoRuntime` exports bootstrap/composition APIs such as `ATProtoHttpServerBuilder`.

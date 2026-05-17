# Endpoint Map Notes

- Current client-side XRPC coverage lives in `packages/atproto-client/`.
- Generated method/type data lives in `packages/atproto-client/lexicons.ts`.
- Dynamic client dispatch is implemented in `packages/atproto-client/client.ts`.
- Raw XRPC transport is implemented in `packages/atproto-client/transport.ts` and `packages/atproto-client/clients/raw.ts`.
- Scenario-level endpoint usage lives in `scripts/scenarios/scenarios/`.

Use repo coverage scripts under `scripts/docs/` for source coverage reports. Use scenario files to identify actively exercised endpoints.

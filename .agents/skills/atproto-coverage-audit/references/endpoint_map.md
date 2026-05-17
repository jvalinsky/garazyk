# Endpoint Map Notes

- Current client-side XRPC coverage lives in `packages/gruszka/`.
- Generated method/type data lives in `packages/gruszka/lexicons.ts`.
- Dynamic client dispatch is implemented in `packages/gruszka/client.ts`.
- Raw XRPC transport is implemented in `packages/gruszka/transport.ts` and `packages/gruszka/clients/raw.ts`.
- Scenario-level endpoint usage lives in `scripts/scenarios/scenarios/`.

Use repo coverage scripts under `scripts/docs/` for source coverage reports. Use scenario files to identify actively exercised endpoints.

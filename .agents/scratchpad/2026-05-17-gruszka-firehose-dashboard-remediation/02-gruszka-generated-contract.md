# Gruszka Generated Contract

## Design

- Generated lexicon metadata should preserve `input.encoding` and `output.encoding` when a body has encoding and no JSON schema.
- Public root type aliases should be exact re-exports from `packages/gruszka/lexicons.ts`, keeping `generated_types.ts` as the compatibility import path.
- Binary generated input:

```ts
export interface BinaryXrpcInput {
  data: Uint8Array;
  contentType: string;
}
```

- Binary generated output:

```ts
export interface BinaryXrpcResponse {
  status: number;
  contentType: string;
  data: Uint8Array;
}
```

## Compatibility Notes

- Existing imports from `@garazyk/gruszka/generated_types` should continue to resolve.
- JSON query/procedure call shapes should remain object-oriented.
- Encoding-only outputs should preserve HTTP status, content type, and bytes instead of returning parsed JSON.
- Generated method metadata should drive dispatch rather than hard-coded NSID exceptions.

## Verification Targets

- `deno task generate-client`
- Focused gruszka generator/client/transport/public API tests.
- Type-negative tests using `// @ts-expect-error` for bad NSIDs, missing params, and malformed procedure inputs.

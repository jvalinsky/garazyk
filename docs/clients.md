# ATProto Clients (`@garazyk/gruszka`)

This package provides a strongly-typed `XrpcClient` that enables easy interaction with any AT Protocol lexicon endpoint.

## Usage

Instantiate the client with a base URL, and then use the generated namespace objects to make calls:

```typescript
import { XrpcClient } from "@garazyk/gruszka";

const client = new XrpcClient("http://localhost:2583");

// Authenticate
const { data: session } = await client.accounts.createSession("alice.test", "password");

// Perform a typed query
const profile = await client.query(
  "app.bsky.actor.getProfile", 
  { actor: "bob.test" }, 
  session.accessJwt
);

console.log(profile.handle);
```

## Regeneration

The typed lexicons are generated dynamically. If the schemas in `/lexicons/` change, regenerate them via:

```bash
cd packages/gruszka
deno run -A scripts/generate.ts
```
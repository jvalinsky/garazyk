# @garazyk/gruszka

A dynamic XRPC client for the AT Protocol, with exact generated Lexicon types
available for all Bluesky and AT Protocol methods.

## Why Gruszka?

In Polish CB radio and amateur radio slang (**slang krótkofalarski**),
**Gruszka** (literally "pear") is the colloquial term for a **handheld
microphone**.

Just as a radio operator uses the _gruszka_ to transmit messages and interact
with the airwaves, this package serves as your "microphone" for the AT Protocol.
It provides the interface necessary to "broadcast" queries, procedures, and
events to the network, making it the essential tool for communicating within the
ATProto ecosystem.

## Installation

```bash
deno add jsr:@garazyk/gruszka
```

## Features

- **Ergonomic Dynamic API**: The root `client.api` proxy supports nested XRPC
  calls with dynamic response bodies for scripting and service exploration.
- **Exact Lexicon Types**: Strong TypeScript definitions for request parameters
  and response data are available from `@garazyk/gruszka/lexicons`.
- **Firehose Client**: Easy ingestion of the ATProto event stream.
- **Chat Viewer**: TUI-based visualization for Bluesky chat conversations.
- **Account Operations**: High-level helpers for account creation and session
  management.

## Public Subpaths

In addition to the root entry, the package exposes these surfaces:

- `@garazyk/gruszka/lexicons` — generated lexicon types.
- `@garazyk/gruszka/lexicon-resolution` — runtime lexicon resolution.
- `@garazyk/gruszka/legacy-clients` — stable client wrappers.
- `@garazyk/gruszka/account-ops` — account and session helpers.
- `@garazyk/gruszka/seed` — fixture generation.
- `@garazyk/gruszka/format` — display formatters.
- `@garazyk/gruszka/doc-links` — repo cross-reference helpers.

## Usage

```typescript
import { XrpcClient } from "@garazyk/gruszka";

const client = new XrpcClient("https://bsky.social");

// Idiomatic nested API access with dynamic response bodies
const profile = await client.api.app.bsky.actor.getProfile({
  actor: "did:plc:...",
});

// Authenticated calls use the same dynamic root proxy
const session = await client.api.com.atproto.server.createSession({
  identifier: "alice.test",
  password: "password",
});

const myProfile = await client.api.app.bsky.actor.getProfile({
  actor: session.did,
}, session.accessJwt);

console.log(myProfile.handle);
```

For strict generated method contracts, import types from
`@garazyk/gruszka/lexicons` and apply them at the boundary that needs exact
Lexicon shapes.

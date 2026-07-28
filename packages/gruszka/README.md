# @garazyk/gruszka

A dynamic XRPC client for the AT Protocol, with exact generated Lexicon types
available for all Bluesky and AT Protocol methods.

## Name

In Polish CB and amateur radio slang (_slang krótkofalarski_), _gruszka_
(literally "pear") is the handheld microphone.

## Installation

```bash
deno add jsr:@garazyk/gruszka
```

## Features

- Dynamic API: the root `client.api` proxy handles nested XRPC calls with
  dynamic response bodies, for scripting and service exploration.
- Exact lexicon types: TypeScript definitions for request parameters and
  response data, from `@garazyk/gruszka/lexicons`.
- Firehose client: ingests the ATProto event stream.
- Chat viewer: TUI rendering of Bluesky chat conversations.
- Account operations: helpers for account creation and session management.

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

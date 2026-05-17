# @garazyk/atproto-client

A strongly typed XRPC client for the AT Protocol, featuring dynamically generated methods for all Bluesky and AT Protocol lexicons.

## Installation

```bash
deno add jsr:@garazyk/atproto-client
```

## Features

- **Lexicon-first API**: Every query and procedure method is derived from official ATProto lexicons.
- **Full Type Safety**: Strong TypeScript definitions for request parameters and response data.
- **Firehose Client**: Easy ingestion of the ATProto event stream.
- **Protocol Seed Helpers**: Utilities for common flows like account creation and record seeding.

## Usage

```typescript
import { XrpcClient } from "@garazyk/atproto-client";

const client = new XrpcClient("https://bsky.social");

// Fully typed query
const profile = await client.query("app.bsky.actor.getProfile", {
  actor: "did:plc:..."
});
console.log(profile.handle);
```

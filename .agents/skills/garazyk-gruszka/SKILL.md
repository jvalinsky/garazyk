---
name: garazyk-gruszka
description: Strongly typed XRPC client, firehose consumer, lexicon resolution, and account utilities for AT Protocol services from the @garazyk/gruszka Deno package. Use when making XRPC calls, consuming the firehose, resolving lexicons dynamically, or generating account credentials.
---

# Garazyk Gruszka — AT Protocol Client

`@garazyk/gruszka` provides a strongly typed XRPC client with actor-scoped sub-clients, firehose consumption, dynamic lexicon resolution, and account utilities. Base package with no import constraints.

## When to Use

- Make XRPC queries or procedures against an AT Protocol service
- Consume the firehose (subscribeRepos) WebSocket stream
- Resolve lexicons dynamically via DNS/DID/record
- Generate invite codes, passwords, or random strings
- Access typed namespace clients (app.bsky, chat.bsky, com.atproto)

## Quick Start

```ts
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import { FirehoseClient, parseFirehoseFrame } from "@garazyk/gruszka";
import { generateInviteCode, generatePassword } from "@garazyk/gruszka";
```

Subpath imports:

```ts
import { resolveLexicon, DenoDnsResolver, HttpDidResolver, HttpRecordFetcher }
  from "@garazyk/gruszka/lexicon-resolution";
import { /* generated lexicon definitions */ } from "@garazyk/gruszka/lexicons";
import { /* hand-written namespace clients */ } from "@garazyk/gruszka/legacy-clients";
import { formatBytes } from "@garazyk/gruszka/format";
```

## API Reference

### XrpcClient

| Export | Type | Description |
|--------|------|-------------|
| `XrpcClient` | class | High-level XRPC client with namespace sub-clients |
| `XrpcError` | class | XRPC-specific error with status and body |
| `client.as(actor)` | → `ActorScopedClient` | Bind all requests to an actor's identity |
| `client.asAdmin(token)` | → `ActorScopedClient` | Bind requests with admin token |
| `client.waitForHealthy()` | async → void | Poll `/_health` until service responds |

### ActorScopedClient

Returned by `client.as(actor)` or `client.asAdmin(token)`. Every request includes the actor's bearer token.

| Property | Type | Description |
|----------|------|-------------|
| `raw` | `ActorRawClient` | Raw XRPC/HTTP methods (get, post, query, procedure, xrpcGet, xrpcPost, postBinary, httpGet, httpPost) |
| `api` | `GeneratedClient` | Fully typed namespace client (e.g., `api.app.bsky.actor.getProfile(...)`) |
| `repo` | `ActorRepoClient` | Record CRUD (createRecord, getRecord, putRecord, deleteRecord, applyWrites, listRecords, describeRepo, listMissingBlobs, uploadBlob) |
| `graph` | `ActorGraphClient` | Social graph (getFollows, getFollowers, getBlocks, getMutes, muteActor, unmuteActor, getRelationships, getStarterPacks, getList, getLists) |
| `feed` | `ActorFeedClient` | Feed/timeline (getProfile, getTimeline, getAuthorFeed, getPostThread, getLikes, searchActors, getActorLikes, getPosts, getRepostedBy, getFeed, getFeedGenerators) |

### Firehose

| Export | Type | Description |
|--------|------|-------------|
| `FirehoseClient` | class | WebSocket client for subscribeRepos |
| `FirehoseEvent` | class | Decoded event (seq, type, payload, header, body) |
| `parseFirehoseFrame(payload)` | function | Parse raw binary frame to header + body |
| `firehoseEventFromFrame(frame)` | function | Convert parsed frame to FirehoseEvent |
| `FirehoseFrameParseError` | class | Error on invalid DAG-CBOR |

### Lexicon Resolution

| Export | Type | Description |
|--------|------|-------------|
| `resolveLexicon(nsid, ports)` | async → `Result` | Dynamic DNS/DID/record lexicon resolution |
| `ResolutionPorts` | type | `{ dns, did, record }` adapter interfaces |
| `DenoDnsResolver` | class | DNS resolution via Deno APIs |
| `HttpDidResolver` | class | DID resolution via HTTP |
| `HttpRecordFetcher` | class | Record fetch via HTTP |

### Account Utilities

| Export | Type | Description |
|--------|------|-------------|
| `generateInviteCode()` | → string | Generate a random invite code |
| `generatePassword()` | → string | Generate a random password |
| `randomString(length)` | → string | Generate a random string |

### Transport

| Export | Type | Description |
|--------|------|-------------|
| `TransportLayer` | class | Low-level HTTP transport with response recording |
| `TransportError` | class | Transport-level error |
| `TransportResponse` | type | `{ method, status, body, time }` |

## Key Patterns

### Create a client and make typed calls

```ts
const client = new XrpcClient("http://localhost:2583");
await client.waitForHealthy();

const luna = client.as(actor);
const profile = await luna.feed.getProfile("alice.test");
const timeline = await luna.feed.getTimeline(25);
```

### Actor-scoped repo operations

```ts
const luna = client.as(actor);
await luna.repo.createRecord({
  collection: "app.bsky.feed.post",
  record: { $type: "app.bsky.feed.post", text: "Hello!", createdAt: new Date().toISOString() },
});
const records = await luna.repo.listRecords({ collection: "app.bsky.feed.post", limit: 10 });
```

### Consume the firehose

```ts
import { FirehoseClient, parseFirehoseFrame } from "@garazyk/gruszka";

const firehose = new FirehoseClient("ws://localhost:2584/xrpc/com.atproto.sync.subscribeRepos");
for await (const event of firehose) {
  console.log(`seq=${event.seq} type=${event.type}`);
}
```

### Resolve a lexicon dynamically

```ts
import { resolveLexicon } from "@garazyk/gruszka/lexicon-resolution";
import { DenoDnsResolver, HttpDidResolver, HttpRecordFetcher } from "@garazyk/gruszka/lexicon-resolution";

const result = await resolveLexicon("app.bsky.feed.post", {
  dns: new DenoDnsResolver(),
  did: new HttpDidResolver(),
  record: new HttpRecordFetcher(),
});
if (result.ok) console.log("Resolved:", result.value.id);
```

## Boundary Rules

Gruszka is the base package with no import constraints. All other packages may import from gruszka.

## Related Skills

- **garazyk-hamownia** — Re-exports `resolveLexicon` and uses XrpcClient for scenarios
- **garazyk-schemat** — Provides service URLs that feed into XrpcClient construction
- **garazyk-laweta** — Docker client used to start services that XrpcClient connects to

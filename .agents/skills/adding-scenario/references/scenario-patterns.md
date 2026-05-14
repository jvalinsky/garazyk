# Scenario Patterns

Common patterns for writing scenarios, derived from the existing suite.

## Table of Contents

- [Account Lifecycle](#account-lifecycle)
- [Content Creation](#content-creation)
- [Social Graph](#social-graph)
- [Federation (PDS2)](#federation-pds2)
- [Admin & Moderation](#admin--moderation)
- [AppView Queries](#appview-queries)
- [Blob Uploads](#blob-uploads)
- [Firehose / Event Streaming](#firehose--event-streaming)
- [Load & Soak](#load--soak)
- [Error / Negative Paths](#error--negative-paths)
- [Skipping & Gating](#skipping--gating)

## Account Lifecycle

```typescript
const char = getCharacter("luna");
const client = new XrpcClient(PDS1);

// Create with fallback to login
const session = await timedCall(
  result, `Create account: ${char.name}`,
  async () => {
    try {
      return (await client.agent.createAccount({
        handle: char.handle, email: char.email, password: char.password,
      })).data;
    } catch (e: any) {
      if (e.message?.includes("already exists")) {
        return (await client.agent.login({
          identifier: char.handle, password: char.password,
        })).data;
      }
      throw e;
    }
  },
  (s) => `did=${s.did}`
);
if (session) {
  char.did = session.did;
  char.accessJwt = session.accessJwt;
  char.refreshJwt = session.refreshJwt;
}

// Verify session
await timedCall(
  result, "Get session",
  async () => {
    return await client.raw.get("com.atproto.server.getSession", {}, char.accessJwt);
  }
);

// Refresh session
const refreshed = await timedCall(
  result, "Refresh session",
  async () => {
    return await client.accounts.refreshSession(char.refreshJwt);
  }
);
if (refreshed) {
  char.accessJwt = refreshed.accessJwt;
  char.refreshJwt = refreshed.refreshJwt;
}
```

## Content Creation

```typescript
function now() { return new Date().toISOString(); }

// Create a post
const post = await timedCall(
  result, `${char.name} posts`,
  async () => {
    return await client.raw.post("com.atproto.repo.createRecord", {
      repo: char.did,
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: "Hello from the scenario!",
        createdAt: now(),
      },
    }, char.accessJwt);
  }
);

// Create a reply
const reply = await timedCall(
  result, `${char.name} replies`,
  async () => {
    return await client.raw.post("com.atproto.repo.createRecord", {
      repo: char.did,
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: "Replying to your post!",
        createdAt: now(),
        reply: {
          root: { uri: post.uri, cid: post.cid },
          parent: { uri: post.uri, cid: post.cid },
        },
      },
    }, char.accessJwt);
  }
);

// Create a like
const like = await timedCall(
  result, `${char.name} likes`,
  async () => {
    return await client.raw.post("com.atproto.repo.createRecord", {
      repo: char.did,
      collection: "app.bsky.feed.like",
      record: {
        $type: "app.bsky.feed.like",
        subject: { uri: post.uri, cid: post.cid },
        createdAt: now(),
      },
    }, char.accessJwt);
  }
);

// Delete a record
await timedCall(
  result, `${char.name} deletes post`,
  async () => {
    await client.raw.post("com.atproto.repo.deleteRecord", {
      repo: char.did,
      collection: "app.bsky.feed.post",
      rkey: postRkey,
    }, char.accessJwt);
  }
);
```

## Social Graph

```typescript
// Follow
await timedCall(
  result, `${follower.name} follows ${target.name}`,
  async () => {
    return await client.raw.post("com.atproto.repo.createRecord", {
      repo: follower.did,
      collection: "app.bsky.graph.follow",
      record: {
        $type: "app.bsky.graph.follow",
        subject: target.did,
        createdAt: now(),
      },
    }, follower.accessJwt);
  }
);

// Verify follow graph
await timedCall(
  result, "Verify follower list",
  async () => {
    const profile = await client.raw.get("app.bsky.actor.getProfile", {
      actor: target.did,
    }, follower.accessJwt);
    if (profile.followersCount < 1) throw new Error("Expected at least 1 follower");
    return profile;
  },
  (p) => `followers=${p.followersCount}`
);

// Block
await timedCall(
  result, `${blocker.name} blocks ${blocked.name}`,
  async () => {
    return await client.raw.post("com.atproto.repo.createRecord", {
      repo: blocker.did,
      collection: "app.bsky.graph.block",
      record: {
        $type: "app.bsky.graph.block",
        subject: blocked.did,
        createdAt: now(),
      },
    }, blocker.accessJwt);
  }
);
```

## Federation (PDS2)

Requires PDS2. Add scenario number to `NEEDS_PDS2` in `run_scenarios.ts`.

```typescript
import { PDS1, PDS2, getCharacter } from "../../lib/deno/config.ts";

const pds1 = new XrpcClient(PDS1);
const pds2 = new XrpcClient(PDS2);

// Health check both PDS
for (const { name, client } of [
  { name: "PDS1", client: pds1 },
  { name: "PDS2", client: pds2 },
]) {
  await timedCall(
    result, `${name} health check`,
    async () => {
      const res = await fetch(`${client.baseUrl}/xrpc/com.atproto.server.describeServer`);
      if (!res.ok) throw new Error(`${name} not healthy`);
    }
  );
}

// Create accounts on PDS2
const nova = getCharacter("nova");  // nova has pdsUrl = PDS2
const session = await timedCall(
  result, `Create account on PDS2: ${nova.name}`,
  async () => {
    try {
      return (await pds2.agent.createAccount({
        handle: nova.handle, email: nova.email, password: nova.password,
      })).data;
    } catch (e: any) {
      if (e.message?.includes("already exists")) {
        return (await pds2.agent.login({
          identifier: nova.handle, password: nova.password,
        })).data;
      }
      throw e;
    }
  },
  (s) => `did=${s.did}`
);
if (session) {
  nova.did = session.did;
  nova.accessJwt = session.accessJwt;
}

// Cross-PDS follow
await timedCall(
  result, "PDS2 user follows PDS1 user",
  async () => {
    await pds2.raw.post("com.atproto.repo.createRecord", {
      repo: nova.did,
      collection: "app.bsky.graph.follow",
      record: {
        $type: "app.bsky.graph.follow",
        subject: luna.did,
        createdAt: now(),
      },
    }, nova.accessJwt);
  }
);
```

## Admin & Moderation

```typescript
// Admin login
const adminClient = new XrpcClient(PDS1);
const adminToken = await timedCall(
  result, "Admin login",
  async () => {
    return await adminClient.adminLogin("admin-localdev");
  }
);

// Submit a report
await timedCall(
  result, "Submit moderation report",
  async () => {
    return await adminClient.raw.post("com.atproto.moderation.createReport", {
      reasonType: "com.atproto.moderation.defs#reasonSpam",
      reason: "Automated test report",
      subject: {
        $type: "com.atproto.repo.strongRef",
        uri: postUri,
        cid: postCid,
      },
    }, luna.accessJwt);
  }
);

// Takedown (admin)
await timedCall(
  result, "Admin applies takedown",
  async () => {
    return await adminClient.raw.post("com.atproto.admin.updateSubjectStatus", {
      subject: { $type: "com.atproto.admin.defs#repoRef", did: troll.did },
      takedown: { applied: true },
    }, adminToken);
  }
);
```

## AppView Queries

```typescript
// Wait for AppView indexing
await new Promise(r => setTimeout(r, 2000));

// Get profile via AppView
const appviewClient = new XrpcClient("http://localhost:3200");
await timedCall(
  result, "AppView profile lookup",
  async () => {
    return await appviewClient.raw.get("app.bsky.actor.getProfile", {
      actor: luna.did,
    }, luna.accessJwt);
  }
);

// Get feed via AppView
await timedCall(
  result, "AppView author feed",
  async () => {
    return await appviewClient.raw.get("app.bsky.feed.getAuthorFeed", {
      actor: luna.did,
    }, luna.accessJwt);
  }
);
```

## Blob Uploads

```typescript
// Upload a text blob
const blob = await timedCall(
  result, "Upload blob",
  async () => {
    const data = new TextEncoder().encode("test blob content");
    return await client.rawTransport.postBinary(
      "com.atproto.repo.uploadBlob",
      data,
      "text/plain",
      luna.accessJwt,
    );
  }
);

// Embed blob in a post
await timedCall(
  result, "Post with blob embed",
  async () => {
    return await client.raw.post("com.atproto.repo.createRecord", {
      repo: luna.did,
      collection: "app.bsky.feed.post",
      record: {
        $type: "app.bsky.feed.post",
        text: "Check out this file!",
        createdAt: now(),
        embed: {
          $type: "app.bsky.embed.external",
          external: {
            uri: "https://example.com",
            title: "Example",
            description: "Test embed",
          },
        },
      },
    }, luna.accessJwt);
  }
);
```

## Firehose / Event Streaming

```typescript
// Subscribe to firehose (WebSocket)
await timedCall(
  result, "Subscribe to firehose",
  async () => {
    const ws = new WebSocket("ws://localhost:2584/xrpc/com.atproto.sync.subscribeRepos");
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("timeout")), 10000);
      ws.onmessage = (event) => {
        // Parse the message
        clearTimeout(timeout);
        resolve(event.data);
      };
      ws.onerror = () => reject(new Error("WebSocket error"));
    });
  }
);
```

## Load & Soak

```typescript
import { OperationTimer, PhaseTimer, scrapePrometheus, sampleStorage } from "../../lib/deno/instrumentation.ts";

const opTimer = new OperationTimer();
const phaseTimer = new PhaseTimer();

// Timed burst
await phaseTimer.run("write_burst", async () => {
  const promises = [];
  for (let i = 0; i < 100; i++) {
    promises.push(opTimer.measure("createRecord", async () => {
      await client.raw.post("com.atproto.repo.createRecord", {
        repo: char.did,
        collection: "app.bsky.feed.post",
        record: { $type: "app.bsky.feed.post", text: `Burst post ${i}`, createdAt: now() },
      }, char.accessJwt);
    }));
  }
  await Promise.all(promises);
});

// Record metrics
result.recordArtifact("operation_timing", opTimer.summary());
result.recordArtifact("phase_timing", phaseTimer.summary());
result.recordArtifact("prometheus", await scrapePrometheus("http://localhost:2583"));
result.recordArtifact("storage", await sampleStorage("/tmp/garazyk-atproto-e2e"));
```

## Error / Negative Paths

```typescript
// Expect a call to fail
await timedCall(
  result, "Write with wrong DID",
  async () => {
    await client.raw.post("com.atproto.repo.createRecord", {
      repo: "did:plc:wrong",
      collection: "app.bsky.feed.post",
      record: { $type: "app.bsky.feed.post", text: "should fail", createdAt: now() },
    }, luna.accessJwt);
  },
  undefined,
  true  // expectFailure = true
);

// Catch and inspect specific errors
try {
  await client.raw.post("com.atproto.repo.createRecord", { ... }, revokedToken);
} catch (e: any) {
  if (e.status === 401) {
    result.stepPassed("Revoked token rejected", `status=${e.status}`);
  } else {
    result.stepFailed("Revoked token rejected", `Unexpected status: ${e.status}`);
  }
}
```

## Skipping & Gating

```typescript
// Skip if a service is unavailable
const videoHealthy = await fetch("http://localhost:2586/_health").then(r => r.ok).catch(() => false);
if (!videoHealthy) {
  result.stepSkipped("Video processing", "Video service not available");
  result.finish();
  return result;
}

// Skip optional steps
result.stepSkipped("OAuth flow", "Not implemented yet");
```

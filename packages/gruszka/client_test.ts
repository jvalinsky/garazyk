import { assertEquals } from "jsr:@std/assert";
import { XrpcClient } from "./client.ts";

const originalFetch = globalThis.fetch;

interface CapturedRequest {
  httpMethod: string;
  xrpcMethod: string;
}

function installCaptureFetch(captured: CapturedRequest[]): void {
  globalThis.fetch = (
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const url = new URL(input.toString());
    captured.push({
      httpMethod: init?.method || "GET",
      xrpcMethod: url.pathname.replace(/^\/xrpc\//, ""),
    });
    return Promise.resolve(
      new Response("{}", {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };
}

function restoreFetch(): void {
  globalThis.fetch = originalFetch;
}

Deno.test("generated API dispatch uses lexicon method types", async () => {
  const captured: CapturedRequest[] = [];
  installCaptureFetch(captured);
  try {
    const client = new XrpcClient("http://localhost:2583");

    await client.api.com.atproto.admin.getAccountTakedown({
      did: "did:plc:test",
    });
    await client.api.com.atproto.admin.resolveReport({ id: 1 });
    await client.api.com.atproto.admin.queryAuditLog({});
    await client.api.app.bsky.unspecced.searchActorsSkeleton({ q: "alice" });

    assertEquals(captured, [
      {
        httpMethod: "POST",
        xrpcMethod: "com.atproto.admin.getAccountTakedown",
      },
      { httpMethod: "POST", xrpcMethod: "com.atproto.admin.resolveReport" },
      { httpMethod: "GET", xrpcMethod: "com.atproto.admin.queryAuditLog" },
      {
        httpMethod: "GET",
        xrpcMethod: "app.bsky.unspecced.searchActorsSkeleton",
      },
    ]);
  } finally {
    restoreFetch();
  }
});

Deno.test("agent dispatch uses lexicon method types", async () => {
  const captured: CapturedRequest[] = [];
  installCaptureFetch(captured);
  try {
    const client = new XrpcClient("http://localhost:2583");

    await client.agent.com.atproto.admin.getAccountTakedown({
      did: "did:plc:test",
    });
    await client.agent.com.atproto.admin.resolveReport({ id: 1 });
    await client.agent.com.atproto.admin.queryAuditLog({});
    await client.agent.app.bsky.unspecced.searchActorsSkeleton({ q: "alice" });

    assertEquals(captured, [
      {
        httpMethod: "POST",
        xrpcMethod: "com.atproto.admin.getAccountTakedown",
      },
      { httpMethod: "POST", xrpcMethod: "com.atproto.admin.resolveReport" },
      { httpMethod: "GET", xrpcMethod: "com.atproto.admin.queryAuditLog" },
      {
        httpMethod: "GET",
        xrpcMethod: "app.bsky.unspecced.searchActorsSkeleton",
      },
    ]);
  } finally {
    restoreFetch();
  }
});

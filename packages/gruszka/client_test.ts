import { assertEquals } from "@std/assert";
import { XrpcClient } from "./client.ts";

const originalFetch = globalThis.fetch;

interface CapturedRequest {
  httpMethod: string;
  xrpcMethod: string;
  contentType?: string;
  bodyIsBinary?: boolean;
}

function installCaptureFetch(captured: CapturedRequest[]): void {
  globalThis.fetch = (
    input: RequestInfo | URL,
    init?: RequestInit,
  ): Promise<Response> => {
    const url = new URL(input.toString());
    const contentType = init?.headers instanceof Headers
      ? init.headers.get("Content-Type") ?? undefined
      : typeof init?.headers === "object" && init.headers !== null &&
          !Array.isArray(init.headers)
      ? (init.headers as Record<string, string>)["Content-Type"]
      : undefined;
    const request: CapturedRequest = {
      httpMethod: init?.method || "GET",
      xrpcMethod: url.pathname.replace(/^\/xrpc\//, ""),
      bodyIsBinary: init?.body instanceof Uint8Array,
    };
    if (contentType !== undefined) request.contentType = contentType;
    captured.push(request);
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
        contentType: "application/json",
        bodyIsBinary: false,
      },
      {
        httpMethod: "POST",
        xrpcMethod: "com.atproto.admin.resolveReport",
        contentType: "application/json",
        bodyIsBinary: false,
      },
      {
        httpMethod: "GET",
        xrpcMethod: "com.atproto.admin.queryAuditLog",
        bodyIsBinary: false,
      },
      {
        httpMethod: "GET",
        xrpcMethod: "app.bsky.unspecced.searchActorsSkeleton",
        bodyIsBinary: false,
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
        contentType: "application/json",
        bodyIsBinary: false,
      },
      {
        httpMethod: "POST",
        xrpcMethod: "com.atproto.admin.resolveReport",
        contentType: "application/json",
        bodyIsBinary: false,
      },
      {
        httpMethod: "GET",
        xrpcMethod: "com.atproto.admin.queryAuditLog",
        bodyIsBinary: false,
      },
      {
        httpMethod: "GET",
        xrpcMethod: "app.bsky.unspecced.searchActorsSkeleton",
        bodyIsBinary: false,
      },
    ]);
  } finally {
    restoreFetch();
  }
});

Deno.test("generated API dispatch routes binary encodings through binary transport", async () => {
  const captured: CapturedRequest[] = [];
  installCaptureFetch(captured);
  try {
    const client = new XrpcClient("http://localhost:2583");

    await client.api.com.atproto.sync.getRepo({ did: "did:plc:test" });
    await client.api.app.bsky.video.uploadVideo(new Uint8Array([1, 2, 3]));
    await client.api.com.atproto.repo.uploadBlob(new Uint8Array([4, 5, 6]));

    assertEquals(captured, [
      {
        httpMethod: "GET",
        xrpcMethod: "com.atproto.sync.getRepo",
        bodyIsBinary: false,
      },
      {
        httpMethod: "POST",
        xrpcMethod: "app.bsky.video.uploadVideo",
        contentType: "video/mp4",
        bodyIsBinary: true,
      },
      {
        httpMethod: "POST",
        xrpcMethod: "com.atproto.repo.uploadBlob",
        contentType: "application/octet-stream",
        bodyIsBinary: true,
      },
    ]);
  } finally {
    restoreFetch();
  }
});

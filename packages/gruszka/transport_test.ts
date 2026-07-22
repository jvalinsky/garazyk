/**
 * Unit tests for TransportLayer — retry logic, error classification,
 * query parameter encoding, and binary response handling.
 *
 * Mocks global fetch to avoid network I/O.
 */

import {
  assertEquals,
  assertInstanceOf,
  type assertRejects,
} from "jsr:@std/assert";
import { TransportError, TransportLayer, XrpcError } from "./transport.ts";

// ---------------------------------------------------------------------------
// Mock fetch infrastructure
// ---------------------------------------------------------------------------

let mockFetch:
  | ((input: RequestInfo | URL, init?: RequestInit) => Promise<Response>)
  | null = null;

const originalFetch = globalThis.fetch;

function installMockFetch(
  impl: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>,
) {
  mockFetch = impl;
  globalThis.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
    if (mockFetch) return mockFetch(input, init);
    return originalFetch(input, init);
  };
}

function restoreFetch() {
  mockFetch = null;
  globalThis.fetch = originalFetch;
}

function jsonResponse(
  body: any,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

function textResponse(text: string, status = 200): Response {
  return new Response(text, { status });
}

// ---------------------------------------------------------------------------
// Tests: XrpcError
// ---------------------------------------------------------------------------

Deno.test("XrpcError: constructs with method, status, body", () => {
  const err = new XrpcError("app.bsky.actor.getProfile", 400, {
    error: "InvalidRequest",
  });
  assertEquals(err.name, "XrpcError");
  assertEquals(err.method, "app.bsky.actor.getProfile");
  assertEquals(err.status, 400);
  assertEquals(err.body, { error: "InvalidRequest" });
  assertInstanceOf(err, Error);
});

// ---------------------------------------------------------------------------
// Tests: TransportError
// ---------------------------------------------------------------------------

Deno.test("TransportError: constructs with method, url, cause, attempt", () => {
  const cause = new TypeError("NetworkError");
  const err = new TransportError(
    "POST",
    "http://localhost/xrpc/test",
    cause,
    3,
  );
  assertEquals(err.name, "TransportError");
  assertEquals(err.method, "POST");
  assertEquals(err.url, "http://localhost/xrpc/test");
  assertEquals(err.attempt, 3);
  assertEquals(err.cause, cause);
  assertInstanceOf(err, Error);
});

// ---------------------------------------------------------------------------
// Tests: GET retries on retryable status
// ---------------------------------------------------------------------------

Deno.test("request: GET retries on 503", async () => {
  let calls = 0;
  installMockFetch(async () => {
    calls++;
    if (calls < 3) return jsonResponse({ error: "ServiceUnavailable" }, 503);
    return jsonResponse({ data: "ok" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    const res = await t.request("GET", "/xrpc/test", { method: "GET" });
    assertEquals(res.status, 200);
    assertEquals(res.body, { data: "ok" });
    assertEquals(calls, 3);
  } finally {
    restoreFetch();
  }
});

Deno.test("request: GET retries on 429", async () => {
  let calls = 0;
  installMockFetch(async () => {
    calls++;
    if (calls < 2) return jsonResponse({ error: "RateLimitExceeded" }, 429);
    return jsonResponse({ data: "ok" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    const res = await t.request("GET", "/xrpc/test", { method: "GET" });
    assertEquals(res.status, 200);
    assertEquals(calls, 2);
  } finally {
    restoreFetch();
  }
});

// ---------------------------------------------------------------------------
// Tests: POST does NOT retry by default
// ---------------------------------------------------------------------------

Deno.test("request: POST does not retry on 503 by default", async () => {
  let calls = 0;
  installMockFetch(async () => {
    calls++;
    return jsonResponse({ error: "ServiceUnavailable" }, 503);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    const res = await t.request("POST", "/xrpc/test", { method: "POST" });
    assertEquals(res.status, 503);
    assertEquals(calls, 1);
  } finally {
    restoreFetch();
  }
});

Deno.test("request: POST retries when maxRetries and allowMutationRetry are set", async () => {
  let calls = 0;
  installMockFetch(async () => {
    calls++;
    if (calls < 2) return jsonResponse({ error: "ServiceUnavailable" }, 503);
    return jsonResponse({ data: "ok" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    const res = await t.request("POST", "/xrpc/test", { method: "POST" }, {
      maxRetries: 3,
      allowMutationRetry: true,
    });
    assertEquals(res.status, 200);
    assertEquals(calls, 2);
  } finally {
    restoreFetch();
  }
});

// ---------------------------------------------------------------------------
// Tests: Network errors
// ---------------------------------------------------------------------------

Deno.test("request: throws TransportError on network failure after max attempts", async () => {
  installMockFetch(async () => {
    throw new TypeError("NetworkError: Failed to fetch");
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.request("GET", "/xrpc/test", { method: "GET" });
    throw new Error("Should have thrown TransportError");
  } catch (e) {
    assertInstanceOf(e, TransportError);
    assertEquals((e as TransportError).attempt, 3);
  } finally {
    restoreFetch();
  }
});

Deno.test("request: POST throws TransportError on first network failure", async () => {
  installMockFetch(async () => {
    throw new TypeError("NetworkError: Failed to fetch");
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.request("POST", "/xrpc/test", { method: "POST" });
    throw new Error("Should have thrown TransportError");
  } catch (e) {
    assertInstanceOf(e, TransportError);
    assertEquals((e as TransportError).attempt, 1);
  } finally {
    restoreFetch();
  }
});

// ---------------------------------------------------------------------------
// Tests: XrpcError thrown on 4xx
// ---------------------------------------------------------------------------

Deno.test("get: throws XrpcError on 400", async () => {
  installMockFetch(async () => {
    return jsonResponse({ error: "InvalidRequest", message: "Bad query" }, 400);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.get("app.bsky.actor.getProfile", { actor: "bad" });
    throw new Error("Should have thrown XrpcError");
  } catch (e) {
    assertInstanceOf(e, XrpcError);
    assertEquals((e as XrpcError).status, 400);
  } finally {
    restoreFetch();
  }
});

Deno.test("post: throws XrpcError on 401", async () => {
  installMockFetch(async () => {
    return jsonResponse({ error: "AuthenticationRequired" }, 401);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.post("com.atproto.repo.createRecord", { record: {} }, "bad-token");
    throw new Error("Should have thrown XrpcError");
  } catch (e) {
    assertInstanceOf(e, XrpcError);
    assertEquals((e as XrpcError).status, 401);
  } finally {
    restoreFetch();
  }
});

// ---------------------------------------------------------------------------
// Tests: Query parameter encoding
// ---------------------------------------------------------------------------

Deno.test("get: encodes query parameters", async () => {
  let capturedUrl = "";
  installMockFetch(async (input) => {
    capturedUrl = input.toString();
    return jsonResponse({ did: "did:plc:test" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.get("app.bsky.actor.getProfile", { actor: "alice.bsky.social" });
    const url = new URL(capturedUrl);
    assertEquals(url.searchParams.get("actor"), "alice.bsky.social");
  } finally {
    restoreFetch();
  }
});

Deno.test("get: skips null/undefined params", async () => {
  let capturedUrl = "";
  installMockFetch(async (input) => {
    capturedUrl = input.toString();
    return jsonResponse({ data: "ok" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.get("test.method", {
      a: "hello",
      b: null,
      c: undefined,
      d: "world",
    });
    const url = new URL(capturedUrl);
    assertEquals(url.searchParams.get("a"), "hello");
    assertEquals(url.searchParams.get("b"), null);
    assertEquals(url.searchParams.get("c"), null);
    assertEquals(url.searchParams.get("d"), "world");
  } finally {
    restoreFetch();
  }
});

Deno.test("get: encodes array params as repeated keys", async () => {
  let capturedUrl = "";
  installMockFetch(async (input) => {
    capturedUrl = input.toString();
    return jsonResponse({ data: "ok" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.get("test.method", {
      collections: ["app.bsky.feed.post", "app.bsky.feed.like"],
    });
    const url = new URL(capturedUrl);
    assertEquals(url.searchParams.getAll("collections"), [
      "app.bsky.feed.post",
      "app.bsky.feed.like",
    ]);
  } finally {
    restoreFetch();
  }
});

// ---------------------------------------------------------------------------
// Tests: Response body parsing
// ---------------------------------------------------------------------------

Deno.test("request: parses JSON response body", async () => {
  installMockFetch(async () => {
    return jsonResponse(
      { did: "did:plc:test", handle: "test.bsky.social" },
      200,
    );
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    const res = await t.request("GET", "/xrpc/test");
    assertEquals(res.body.did, "did:plc:test");
    assertEquals(res.body.handle, "test.bsky.social");
  } finally {
    restoreFetch();
  }
});

Deno.test("request: returns text body when response is not JSON", async () => {
  installMockFetch(async () => {
    return textResponse("plain text response", 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    const res = await t.request("GET", "/xrpc/test");
    assertEquals(res.body, "plain text response");
  } finally {
    restoreFetch();
  }
});

// ---------------------------------------------------------------------------
// Tests: Response recording
// ---------------------------------------------------------------------------

Deno.test("request: records responses in lastResponses", async () => {
  installMockFetch(async () => {
    return jsonResponse({ data: "ok" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    await t.request("GET", "/xrpc/test1");
    await t.request("GET", "/xrpc/test2");
    assertEquals(t.lastResponses.length, 2);
    assertEquals(t.lastResponse?.method, "GET");
    assertEquals(t.lastResponse?.status, 200);
  } finally {
    restoreFetch();
  }
});

// ---------------------------------------------------------------------------
// Tests: Base URL normalization
// ---------------------------------------------------------------------------

Deno.test("TransportLayer: strips trailing slash from baseUrl", () => {
  const t = new TransportLayer("http://localhost:2583/");
  assertEquals(t.baseUrl, "http://localhost:2583");
});

// ---------------------------------------------------------------------------
// Tests: custom retryableStatuses
// ---------------------------------------------------------------------------

Deno.test("request: custom retryableStatuses overrides defaults", async () => {
  let calls = 0;
  installMockFetch(async () => {
    calls++;
    if (calls < 2) return jsonResponse({ error: "InternalError" }, 500);
    return jsonResponse({ data: "ok" }, 200);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    // 500 is not in default retryable statuses, but we add it
    const res = await t.request("GET", "/xrpc/test", { method: "GET" }, {
      retryableStatuses: [500, 502, 503, 504],
    });
    assertEquals(res.status, 200);
    assertEquals(calls, 2);
  } finally {
    restoreFetch();
  }
});

Deno.test("request: 500 is NOT retried by default", async () => {
  let calls = 0;
  installMockFetch(async () => {
    calls++;
    return jsonResponse({ error: "InternalError" }, 500);
  });

  try {
    const t = new TransportLayer("http://localhost:2583");
    const res = await t.request("GET", "/xrpc/test", { method: "GET" });
    assertEquals(res.status, 500);
    assertEquals(calls, 1);
  } finally {
    restoreFetch();
  }
});

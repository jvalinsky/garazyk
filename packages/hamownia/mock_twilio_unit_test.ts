/**
 * Unit tests for handleMockTwilioRequest and parseMockTwilioConfig.
 *
 * Calls the exported handler directly — no subprocess or running server needed.
 *
 * @module mock_twilio_unit_test
 */

import { assertEquals, assertMatch } from "@std/assert";
import {
  handleMockTwilioRequest,
  type MockTwilioServerConfig,
  MockTwilioState,
  parseMockTwilioConfig,
} from "./mock_twilio.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeConfig(
  overrides: Partial<MockTwilioServerConfig> = {},
): MockTwilioServerConfig {
  return {
    port: 8099,
    accountSid: "ACtest00000000000000000000000000",
    authToken: "SKtesttoken000000000000000000000",
    alwaysApprove: ["000000"],
    latency: 0,
    failRate: 0,
    ...overrides,
  };
}

function makeState(alwaysApprove?: string[]): MockTwilioState {
  const s = new MockTwilioState();
  if (alwaysApprove) s.alwaysApproveCodes = alwaysApprove;
  return s;
}

function basicAuth(sid: string, token: string): string {
  return "Basic " + btoa(`${sid}:${token}`);
}

function controlReq(path: string, method = "GET"): Request {
  return new Request(`http://localhost:8099${path}`, { method });
}

function controlPost(path: string, body: unknown): Request {
  return new Request(`http://localhost:8099${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

const VERIFY_BASE = "/v2/Service/VA00000000000000000000000000000000";

function verifyReq(
  path: string,
  body: Record<string, string>,
  auth = true,
  config = makeConfig(),
): Request {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (auth) {
    headers["authorization"] = basicAuth(config.accountSid, config.authToken);
  }
  return new Request(`http://localhost:8099${VERIFY_BASE}/${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

// ---------------------------------------------------------------------------
// Control endpoints
// ---------------------------------------------------------------------------

Deno.test("handleMockTwilioRequest: GET /__control/health returns ok", async () => {
  const config = makeConfig();
  const state = makeState();
  const res = await handleMockTwilioRequest(
    controlReq("/__control/health"),
    config,
    state,
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "ok");
  assertEquals(typeof body.uptime, "number");
  assertEquals(body.uptime >= 0, true);
});

Deno.test("handleMockTwilioRequest: GET /__control/state returns store and codes", async () => {
  const config = makeConfig();
  const state = makeState();
  state.store["+15555550001"] = {
    code: "123456",
    createdAt: 0,
    verified: false,
  };
  const res = await handleMockTwilioRequest(
    controlReq("/__control/state"),
    config,
    state,
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.store["+15555550001"].code, "123456");
  assertEquals(Array.isArray(body.alwaysApproveCodes), true);
});

Deno.test("handleMockTwilioRequest: POST /__control/reset clears state", async () => {
  const config = makeConfig();
  const state = makeState();
  state.store["+15555550002"] = {
    code: "999999",
    createdAt: 0,
    verified: false,
  };
  await handleMockTwilioRequest(
    controlPost("/__control/reset", {}),
    config,
    state,
  );
  assertEquals(Object.keys(state.store).length, 0);
});

Deno.test("handleMockTwilioRequest: POST /__control/setCode stores code", async () => {
  const config = makeConfig();
  const state = makeState();
  const res = await handleMockTwilioRequest(
    controlPost("/__control/setCode", {
      phone: "+15555550003",
      code: "654321",
    }),
    config,
    state,
  );
  assertEquals(res.status, 200);
  assertEquals(state.store["+15555550003"].code, "654321");
  assertEquals(state.store["+15555550003"].verified, false);
});

Deno.test("handleMockTwilioRequest: POST /__control/setCode missing phone returns 400", async () => {
  const res = await handleMockTwilioRequest(
    controlPost("/__control/setCode", { code: "123456" }),
    makeConfig(),
    makeState(),
  );
  assertEquals(res.status, 400);
});

Deno.test("handleMockTwilioRequest: POST /__control/setCode missing code returns 400", async () => {
  const res = await handleMockTwilioRequest(
    controlPost("/__control/setCode", { phone: "+15555550004" }),
    makeConfig(),
    makeState(),
  );
  assertEquals(res.status, 400);
});

Deno.test("handleMockTwilioRequest: POST /__control/setAlwaysApprove updates codes", async () => {
  const config = makeConfig();
  const state = makeState();
  const res = await handleMockTwilioRequest(
    controlPost("/__control/setAlwaysApprove", { codes: ["aaa", "bbb"] }),
    config,
    state,
  );
  assertEquals(res.status, 200);
  assertEquals(state.alwaysApproveCodes, ["aaa", "bbb"]);
});

Deno.test("handleMockTwilioRequest: POST /__control/setAlwaysApprove non-array returns 400", async () => {
  const res = await handleMockTwilioRequest(
    controlPost("/__control/setAlwaysApprove", { codes: "not-an-array" }),
    makeConfig(),
    makeState(),
  );
  assertEquals(res.status, 400);
});

// ---------------------------------------------------------------------------
// Verifications POST
// ---------------------------------------------------------------------------

Deno.test("handleMockTwilioRequest: Verifications POST valid → 200 pending", async () => {
  const config = makeConfig();
  const state = makeState();
  const res = await handleMockTwilioRequest(
    verifyReq(
      "Verifications",
      { To: "+15555550010", Channel: "sms" },
      true,
      config,
    ),
    config,
    state,
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "pending");
  assertMatch(body.sid, /^VE[a-f0-9]{32}$/);
  assertEquals(state.store["+15555550010"] !== undefined, true);
});

Deno.test("handleMockTwilioRequest: Verifications POST bad auth → 401", async () => {
  const config = makeConfig();
  const res = await handleMockTwilioRequest(
    verifyReq("Verifications", { To: "+15555550011" }, false, config),
    config,
    makeState(),
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.code, 20003);
});

Deno.test("handleMockTwilioRequest: Verifications POST wrong token → 401", async () => {
  const config = makeConfig();
  const req = new Request(
    `http://localhost:8099${VERIFY_BASE}/Verifications`,
    {
      method: "POST",
      headers: {
        "authorization": basicAuth(config.accountSid, "wrongtoken"),
        "content-type": "application/json",
      },
      body: JSON.stringify({ To: "+15555550012" }),
    },
  );
  const res = await handleMockTwilioRequest(req, config, makeState());
  assertEquals(res.status, 401);
});

Deno.test("handleMockTwilioRequest: Verifications POST missing To → 400", async () => {
  const config = makeConfig();
  const req = new Request(
    `http://localhost:8099${VERIFY_BASE}/Verifications`,
    {
      method: "POST",
      headers: {
        "authorization": basicAuth(config.accountSid, config.authToken),
        "content-type": "application/json",
      },
      body: JSON.stringify({ Channel: "sms" }),
    },
  );
  const res = await handleMockTwilioRequest(req, config, makeState());
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.code, 20005);
});

// ---------------------------------------------------------------------------
// VerificationCheck POST
// ---------------------------------------------------------------------------

Deno.test("handleMockTwilioRequest: VerificationCheck correct code → approved", async () => {
  const config = makeConfig();
  const state = makeState();
  state.store["+15555550020"] = {
    code: "123456",
    createdAt: Date.now(),
    verified: false,
  };

  const res = await handleMockTwilioRequest(
    verifyReq(
      "VerificationCheck",
      { To: "+15555550020", Code: "123456" },
      true,
      config,
    ),
    config,
    state,
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "approved");
  assertEquals(body.valid, true);
  assertEquals(state.store["+15555550020"].verified, true);
});

Deno.test("handleMockTwilioRequest: VerificationCheck wrong code → pending", async () => {
  const config = makeConfig();
  const state = makeState();
  state.store["+15555550021"] = {
    code: "123456",
    createdAt: Date.now(),
    verified: false,
  };

  const res = await handleMockTwilioRequest(
    verifyReq(
      "VerificationCheck",
      { To: "+15555550021", Code: "999999" },
      true,
      config,
    ),
    config,
    state,
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "pending");
  assertEquals(body.valid, false);
  assertEquals(state.store["+15555550021"].verified, false);
});

Deno.test("handleMockTwilioRequest: VerificationCheck always-approve code → approved without store entry", async () => {
  const config = makeConfig({ alwaysApprove: ["000000"] });
  const state = makeState(["000000"]);
  // No entry in store for this phone

  const res = await handleMockTwilioRequest(
    verifyReq(
      "VerificationCheck",
      { To: "+15555550022", Code: "000000" },
      true,
      config,
    ),
    config,
    state,
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "approved");
  assertEquals(body.valid, true);
});

Deno.test("handleMockTwilioRequest: VerificationCheck always-approve does not create store entry", async () => {
  const config = makeConfig({ alwaysApprove: ["000000"] });
  const state = makeState(["000000"]);

  await handleMockTwilioRequest(
    verifyReq(
      "VerificationCheck",
      { To: "+15555550023", Code: "000000" },
      true,
      config,
    ),
    config,
    state,
  );
  // No store entry should have been created for this phone
  assertEquals(state.store["+15555550023"], undefined);
});

Deno.test("handleMockTwilioRequest: VerificationCheck bad auth → 401", async () => {
  const config = makeConfig();
  const res = await handleMockTwilioRequest(
    verifyReq(
      "VerificationCheck",
      { To: "+15555550024", Code: "123456" },
      false,
      config,
    ),
    config,
    makeState(),
  );
  assertEquals(res.status, 401);
});

Deno.test("handleMockTwilioRequest: VerificationCheck missing Code → 400", async () => {
  const config = makeConfig();
  const req = new Request(
    `http://localhost:8099${VERIFY_BASE}/VerificationCheck`,
    {
      method: "POST",
      headers: {
        "authorization": basicAuth(config.accountSid, config.authToken),
        "content-type": "application/json",
      },
      body: JSON.stringify({ To: "+15555550025" }),
    },
  );
  const res = await handleMockTwilioRequest(req, config, makeState());
  assertEquals(res.status, 400);
});

Deno.test("handleMockTwilioRequest: VerificationCheck missing To → 400", async () => {
  const config = makeConfig();
  const req = new Request(
    `http://localhost:8099${VERIFY_BASE}/VerificationCheck`,
    {
      method: "POST",
      headers: {
        "authorization": basicAuth(config.accountSid, config.authToken),
        "content-type": "application/json",
      },
      body: JSON.stringify({ Code: "123456" }),
    },
  );
  const res = await handleMockTwilioRequest(req, config, makeState());
  assertEquals(res.status, 400);
});

// ---------------------------------------------------------------------------
// Catch-all
// ---------------------------------------------------------------------------

Deno.test("handleMockTwilioRequest: unknown path → 404", async () => {
  const res = await handleMockTwilioRequest(
    controlReq("/unknown/path"),
    makeConfig(),
    makeState(),
  );
  assertEquals(res.status, 404);
  const body = await res.json();
  assertEquals(body.error, "Not found");
});

// ---------------------------------------------------------------------------
// parseMockTwilioConfig
// ---------------------------------------------------------------------------

Deno.test("parseMockTwilioConfig: defaults from empty args", () => {
  // Clear env vars that might interfere
  const portOrig = Deno.env.get("PORT");
  const sidOrig = Deno.env.get("TWILIO_ACCOUNT_SID");
  const tokenOrig = Deno.env.get("TWILIO_AUTH_TOKEN");
  const approveOrig = Deno.env.get("ALWAYS_APPROVE_CODES");
  Deno.env.delete("PORT");
  Deno.env.delete("TWILIO_ACCOUNT_SID");
  Deno.env.delete("TWILIO_AUTH_TOKEN");
  Deno.env.delete("ALWAYS_APPROVE_CODES");
  try {
    const config = parseMockTwilioConfig([]);
    assertEquals(config.port, 8081);
    assertEquals(config.accountSid, "AC00000000000000000000000000000000");
    assertEquals(config.authToken, "SK00000000000000000000000000000000");
    assertEquals(config.alwaysApprove, ["000000"]);
    assertEquals(config.latency, 0);
    assertEquals(config.failRate, 0);
  } finally {
    if (portOrig !== undefined) Deno.env.set("PORT", portOrig);
    if (sidOrig !== undefined) Deno.env.set("TWILIO_ACCOUNT_SID", sidOrig);
    if (tokenOrig !== undefined) Deno.env.set("TWILIO_AUTH_TOKEN", tokenOrig);
    if (approveOrig !== undefined) {
      Deno.env.set("ALWAYS_APPROVE_CODES", approveOrig);
    }
  }
});

Deno.test("parseMockTwilioConfig: explicit flag values", () => {
  const config = parseMockTwilioConfig([
    "--port",
    "9999",
    "--account-sid",
    "ACcustom",
    "--auth-token",
    "SKcustom",
  ]);
  assertEquals(config.port, 9999);
  assertEquals(config.accountSid, "ACcustom");
  assertEquals(config.authToken, "SKcustom");
});

Deno.test("parseMockTwilioConfig: --always-approve comma-separated", () => {
  const config = parseMockTwilioConfig(["--always-approve", "aaa,bbb,ccc"]);
  assertEquals(config.alwaysApprove, ["aaa", "bbb", "ccc"]);
});

Deno.test("parseMockTwilioConfig: --latency and --fail-rate", () => {
  const config = parseMockTwilioConfig([
    "--latency",
    "50",
    "--fail-rate",
    "0.1",
  ]);
  assertEquals(config.latency, 50);
  assertEquals(config.failRate, 0.1);
});

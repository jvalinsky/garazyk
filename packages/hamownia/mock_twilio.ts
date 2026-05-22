/** Mock Twilio SMS verification server for E2E testing. @module mock_twilio */
import { parseArgs } from "@std/cli/parse-args";

/** State for a single verification code tracked by the mock server. */
export interface MockVerificationState {
  /** The verification code sent to the user. */
  code: string;
  /** Timestamp when the code was created. */
  createdAt: number;
  /** Whether the code has been verified. */
  verified: boolean;
}

/** Serializable snapshot of the mock Twilio server state. */
export interface MockState {
  /** Verification records keyed by phone number. */
  store: Record<string, MockVerificationState>;
  /** Codes that should be approved without verification. */
  alwaysApproveCodes: string[];
}

/** Per-instance state for a mock Twilio server. */
export class MockTwilioState {
  /** Verification records keyed by phone number. */
  store: Record<string, MockVerificationState> = {};
  /** Codes that are always approved. */
  alwaysApproveCodes: string[] = ["000000"];
  /** Server start timestamp in milliseconds. */
  readonly startTime: number = Date.now();

  /** Reset the store and always-approve codes to defaults. */
  reset(): void {
    for (const key of Object.keys(this.store)) delete this.store[key];
    this.alwaysApproveCodes = ["000000"];
  }
}

/** Serializable snapshot of the mock Twilio server state. */
export interface MockState {
  /** Verification records keyed by phone number. */
  store: Record<string, MockVerificationState>;
  /** Codes that should be approved without verification. */
  alwaysApproveCodes: string[];
}

/** Configuration for the mock Twilio server process. */
export interface MockTwilioServerConfig {
  /** Port to listen on. */
  port: number;
  /** Twilio account SID for basic auth. */
  accountSid: string;
  /** Twilio auth token for basic auth. */
  authToken: string;
  /** Codes that always pass verification. */
  alwaysApprove: string[];
  /** Simulated network latency in milliseconds. */
  latency?: number;
  /** Probability (0-1) of simulated request failures. */
  failRate?: number;
}

/** Split a comma-separated string of codes into a trimmed array. */
function normalizeAlwaysApprove(value: string): string[] {
  return value.split(",").map((s) => s.trim());
}

/** Parse CLI flags and environment variables into a mock Twilio config. */
export function parseMockTwilioConfig(args: string[]): MockTwilioServerConfig {
  const parsed = parseArgs(args, {
    string: [
      "port",
      "account-sid",
      "auth-token",
      "always-approve",
      "latency",
      "fail-rate",
    ],
  }) as Record<string, string | boolean | undefined>;

  return {
    port: Number(parsed.port ?? Deno.env.get("PORT") ?? "8081"),
    accountSid: String(
      parsed["account-sid"] ?? Deno.env.get("TWILIO_ACCOUNT_SID") ??
        "AC00000000000000000000000000000000",
    ),
    authToken: String(
      parsed["auth-token"] ?? Deno.env.get("TWILIO_AUTH_TOKEN") ??
        "SK00000000000000000000000000000000",
    ),
    alwaysApprove: normalizeAlwaysApprove(
      String(
        parsed["always-approve"] ?? Deno.env.get("ALWAYS_APPROVE_CODES") ??
          "000000",
      ),
    ),
    latency: Number(parsed.latency ?? Deno.env.get("LATENCY_MS") ?? "0"),
    failRate: Number(parsed["fail-rate"] ?? Deno.env.get("FAIL_RATE") ?? "0"),
  };
}

/** Generate a random 6-digit verification code. */
function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/** Generate a random Twilio-format verification SID. */
function randomSid(): string {
  const chars = "abcdef0123456789";
  let sid = "VE";
  for (let i = 0; i < 32; i++) {
    sid += chars[Math.floor(Math.random() * chars.length)];
  }
  return sid;
}

/** Decode a Basic auth header into user/pass or null on failure. */
function parseBasicAuth(
  authHeader: string | null,
): { user: string; pass: string } | null {
  if (!authHeader || !authHeader.startsWith("Basic ")) return null;
  try {
    const decoded = atob(authHeader.slice(6));
    const colon = decoded.indexOf(":");
    if (colon === -1) return null;
    return { user: decoded.slice(0, colon), pass: decoded.slice(colon + 1) };
  } catch {
    return null;
  }
}

/** Simulate network latency by delaying for the given number of milliseconds. */
async function maybeLatency(ms: number) {
  if (ms > 0) await new Promise((r) => setTimeout(r, ms));
}

/** Simulate a random request failure based on the configured fail rate. */
async function maybeFail(failRate: number): Promise<boolean> {
  if (failRate > 0 && Math.random() < failRate) return true;
  return false;
}

/** Build a JSON Response with the given body and status code. */
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/** Handle a single mock Twilio HTTP request. */
export async function handleMockTwilioRequest(
  req: Request,
  config: MockTwilioServerConfig,
  state: MockTwilioState,
): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  if (path === "/__control/health") {
    return jsonResponse({ status: "ok", uptime: Date.now() - state.startTime });
  }

  if (path === "/__control/state") {
    return jsonResponse({ store: state.store, alwaysApproveCodes: state.alwaysApproveCodes });
  }

  if (path === "/__control/reset" && req.method === "POST") {
    state.reset();
    return jsonResponse({ status: "ok" });
  }

  if (path === "/__control/setCode" && req.method === "POST") {
    const body = await req.json();
    if (!body.phone || !body.code) {
      return jsonResponse({ error: "phone and code required" }, 400);
    }
    state.store[body.phone] = {
      code: body.code,
      createdAt: Date.now(),
      verified: false,
    };
    return jsonResponse({ status: "ok" });
  }

  if (path === "/__control/setAlwaysApprove" && req.method === "POST") {
    const body = await req.json();
    if (!Array.isArray(body.codes)) {
      return jsonResponse({ error: "codes array required" }, 400);
    }
    state.alwaysApproveCodes = body.codes;
    return jsonResponse({ status: "ok" });
  }

  // ── Twilio Verify API ────────────────────────────────────────────────────

  // Match: /v2/Service/{serviceSID}/Verifications or /{serviceSID}/Verifications
  const verificationsMatch = path.match(
    /^(?:\/v2\/Service)?\/([^/]+)\/Verifications$/,
  );
  if (verificationsMatch && req.method === "POST") {
    await maybeLatency(config.latency ?? 0);
    if (await maybeFail(config.failRate ?? 0)) {
      return jsonResponse({
        status: 500,
        message: "Simulated server error",
        code: 20001,
      }, 500);
    }

    const creds = parseBasicAuth(req.headers.get("authorization"));
    if (
      !creds || creds.user !== config.accountSid ||
      creds.pass !== config.authToken
    ) {
      return jsonResponse({
        status: 401,
        message: "Invalid credentials",
        code: 20003,
      }, 401);
    }

    const body = await req.json();
    const phone: string = body.To || "";
    if (!phone) {
      return jsonResponse({
        status: 400,
        message: "Missing 'To' parameter",
        code: 20005,
      }, 400);
    }

    const code = generateCode();
    state.store[phone] = { code, createdAt: Date.now(), verified: false };

    console.error(`[mock-twilio] Verifications: +${phone} -> code=${code}`);

    return jsonResponse({
      status: "pending",
      sid: randomSid(),
      to: phone,
      channel: body.Channel || "sms",
      valid: false,
      date_created: new Date().toUTCString(),
      service_sid: verificationsMatch[1],
      url: `${url.origin}${path}/${randomSid()}`,
    });
  }

  // Match: /v2/Service/{serviceSID}/VerificationCheck or /{serviceSID}/VerificationCheck
  const checkMatch = path.match(/^(?:\/v2\/Service)?\/([^/]+)\/VerificationCheck$/);
  if (checkMatch && req.method === "POST") {
    await maybeLatency(config.latency ?? 0);
    if (await maybeFail(config.failRate ?? 0)) {
      return jsonResponse({
        status: 500,
        message: "Simulated server error",
        code: 20001,
      }, 500);
    }

    const creds = parseBasicAuth(req.headers.get("authorization"));
    if (
      !creds || creds.user !== config.accountSid ||
      creds.pass !== config.authToken
    ) {
      return jsonResponse({
        status: 401,
        message: "Invalid credentials",
        code: 20003,
      }, 401);
    }

    const body = await req.json();
    const phone: string = body.To || "";
    const code: string = body.Code || "";

    if (!phone || !code) {
      return jsonResponse({
        status: 400,
        message: "Missing 'To' or 'Code'",
        code: 20005,
      }, 400);
    }

    const stored = state.store[phone];
    const isApproved = (stored && stored.code === code) ||
      state.alwaysApproveCodes.includes(code);

    if (isApproved && stored) {
      stored.verified = true;
    }

    console.error(
      `[mock-twilio] VerificationCheck: +${phone} code=${code} -> ${
        isApproved ? "approved" : "pending"
      }`,
    );

    const sid = randomSid();
    return jsonResponse({
      status: isApproved ? "approved" : "pending",
      sid,
      to: phone,
      valid: isApproved,
      date_created: new Date().toUTCString(),
      service_sid: checkMatch[1],
    });
  }

  // ── 404 ──────────────────────────────────────────────────────────────────
  return jsonResponse({ error: "Not found", path }, 404);
}

/** Start a mock Twilio server with the provided configuration. */
export function serveMockTwilio(config: MockTwilioServerConfig): void {
  const state = new MockTwilioState();
  state.alwaysApproveCodes = [...config.alwaysApprove];

  console.error(`[mock-twilio] Starting on port ${config.port}`);
  console.error(
    `[mock-twilio] Always-approve codes: ${state.alwaysApproveCodes.join(", ")}`,
  );
  console.error(`[mock-twilio] Account SID: ${config.accountSid}`);
  if ((config.latency ?? 0) > 0) {
    console.error(`[mock-twilio] Simulated latency: ${config.latency}ms`);
  }
  if ((config.failRate ?? 0) > 0) {
    console.error(`[mock-twilio] Simulated fail rate: ${config.failRate}`);
  }

  void Deno.serve(
    { port: config.port, hostname: "0.0.0.0" },
    (req) => handleMockTwilioRequest(req, config, state),
  );
}

/** Client for controlling a mock Twilio server via its __control HTTP API. */
export class MockTwilioServer {
  private baseUrl: string;
  private process: Deno.ChildProcess | null = null;
  private port: number;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
    this.port = new URL(baseUrl).port ? parseInt(new URL(baseUrl).port) : 8081;
  }

  /** Returns the base URL for the mock Twilio server. */
  get url(): string {
    return this.baseUrl;
  }

  /** Waits until the server responds successfully to the health check. @param timeoutMs - Maximum time to wait in milliseconds. @throws If the server does not become healthy before the timeout expires. */
  async waitForHealth(timeoutMs = 10000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      try {
        const res = await fetch(`${this.baseUrl}/__control/health`);
        const ok = res.ok;
        await res.body?.cancel();
        if (ok) return;
      } catch {
        // server not ready yet
      }
      await new Promise((r) => setTimeout(r, 200));
    }
    throw new Error(`Mock Twilio server not healthy after ${timeoutMs}ms`);
  }

  /** Sets the verification code for a phone number. @param phone - Phone number to update. @param code - Verification code to store. @returns A promise that resolves when the code is updated. @throws If the control endpoint returns a non-OK response. */
  async setCode(phone: string, code: string): Promise<void> {
    const res = await fetch(`${this.baseUrl}/__control/setCode`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone, code }),
    });
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to set code: ${res.status} ${body}`);
    }
  }

  /** Marks verification codes that should always be approved. @param codes - Codes to approve without verification. @returns A promise that resolves when the codes are updated. @throws If the control endpoint returns a non-OK response. */
  async setAlwaysApprove(codes: string[]): Promise<void> {
    const res = await fetch(`${this.baseUrl}/__control/setAlwaysApprove`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ codes }),
    });
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to set always-approve: ${res.status} ${body}`);
    }
  }

  /** Returns the current server state snapshot. @returns A promise that resolves to the current mock server state. @throws If the control endpoint returns a non-OK response. */
  async getState(): Promise<MockState> {
    const res = await fetch(`${this.baseUrl}/__control/state`);
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to get state: ${res.status} ${body}`);
    }
    return JSON.parse(body);
  }

  /** Resets the mock server state. @returns A promise that resolves when the state has been cleared. @throws If the control endpoint returns a non-OK response. */
  async reset(): Promise<void> {
    const res = await fetch(`${this.baseUrl}/__control/reset`, {
      method: "POST",
    });
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to reset: ${res.status} ${body}`);
    }
  }

  /** Checks whether the server responds successfully to the health endpoint. @returns A promise that resolves to true when the server is healthy, otherwise false. */
  async getHealth(): Promise<boolean> {
    try {
      const res = await fetch(`${this.baseUrl}/__control/health`);
      const ok = res.ok;
      await res.body?.cancel();
      return ok;
    } catch {
      return false;
    }
  }

  /** Starts the mock Twilio server process if it is not already running. @returns Nothing. @throws If spawning the process fails. */
  startProcess(): void {
    if (this.process) return;
    const root = new URL("../../", import.meta.url).pathname;
    const cmd = new Deno.Command("deno", {
      args: [
        "run",
        "-A",
        "--config",
        `${root}deno.json`,
        new URL("./mock_twilio_server.ts", import.meta.url)
          .pathname,
        `--port=${this.port}`,
      ],
      stdout: "null",
      stderr: "inherit",
    });
    this.process = cmd.spawn();
  }

  /** Stops the mock Twilio server process if it is running. @returns Nothing. */
  stopProcess(): void {
    if (this.process) {
      try {
        this.process.kill("SIGTERM");
      } catch { /* ignore */ }
      this.process = null;
    }
  }
}

/** Start a mock Twilio server process and wait for it to become healthy. */
export async function startMockTwilioServer(
  port = 8081,
): Promise<MockTwilioServer> {
  const server = new MockTwilioServer(`http://127.0.0.1:${port}`);
  server.startProcess();
  try {
    await server.waitForHealth();
    return server;
  } catch (e) {
    server.stopProcess();
    throw e;
  }
}

/** Stop a mock Twilio server process. Accepts undefined for safe teardown. */
export function stopMockTwilioServer(
  server: MockTwilioServer | undefined,
): void {
  server?.stopProcess();
}

if (import.meta.main) {
  serveMockTwilio(parseMockTwilioConfig(Deno.args));
}

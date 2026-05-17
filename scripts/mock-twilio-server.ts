#!/usr/bin/env -S deno run -A
import { parseArgs } from "@std/cli/parse-args";

interface VerificationState {
  code: string;
  createdAt: number;
  verified: boolean;
}

interface VerificationsStore {
  [phone: string]: VerificationState;
}

const store: VerificationsStore = {};
let alwaysApproveCodes: string[] = ["000000"];

function parseFlags(): typeof defaults {
  const args = parseArgs(Deno.args, { string: ["always-approve"] }) as any;
  return {
    port: Number(args.port ?? Deno.env.get("PORT") ?? "8081"),
    accountSid: String(args["account-sid"] ?? Deno.env.get("TWILIO_ACCOUNT_SID") ??
      "AC00000000000000000000000000000000"),
    authToken: String(args["auth-token"] ?? Deno.env.get("TWILIO_AUTH_TOKEN") ??
      "SK00000000000000000000000000000000"),
    alwaysApprove: String(args["always-approve"] ?? Deno.env.get("ALWAYS_APPROVE_CODES") ?? "000000"),
    latency: Number(args.latency ?? Deno.env.get("LATENCY_MS") ?? "0"),
    failRate: Number(args["fail-rate"] ?? Deno.env.get("FAIL_RATE") ?? "0"),
  };
}

const defaults = {
  port: 8081,
  accountSid: "AC00000000000000000000000000000000",
  authToken: "SK00000000000000000000000000000000",
  alwaysApprove: "000000",
  latency: 0,
  failRate: 0,
};

function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function randomSid(): string {
  const chars = "abcdef0123456789";
  let sid = "VE";
  for (let i = 0; i < 32; i++) {
    sid += chars[Math.floor(Math.random() * chars.length)];
  }
  return sid;
}

function parseBasicAuth(authHeader: string | null): { user: string; pass: string } | null {
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

async function maybeLatency(ms: number) {
  if (ms > 0) await new Promise((r) => setTimeout(r, ms));
}

async function maybeFail(failRate: number): Promise<boolean> {
  if (failRate > 0 && Math.random() < failRate) return true;
  return false;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function handleRequest(req: Request, cfg: ReturnType<typeof parseFlags>): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  // ── Control API ──────────────────────────────────────────────────────────

  if (path === "/__control/health") {
    return jsonResponse({ status: "ok", uptime: Date.now() - startTime });
  }

  if (path === "/__control/state") {
    return jsonResponse({ store, alwaysApproveCodes });
  }

  if (path === "/__control/reset" && req.method === "POST") {
    for (const key of Object.keys(store)) delete store[key];
    alwaysApproveCodes = ["000000"];
    return jsonResponse({ status: "ok" });
  }

  if (path === "/__control/setCode" && req.method === "POST") {
    const body = await req.json();
    if (!body.phone || !body.code) {
      return jsonResponse({ error: "phone and code required" }, 400);
    }
    store[body.phone] = { code: body.code, createdAt: Date.now(), verified: false };
    return jsonResponse({ status: "ok" });
  }

  if (path === "/__control/setAlwaysApprove" && req.method === "POST") {
    const body = await req.json();
    if (!Array.isArray(body.codes)) {
      return jsonResponse({ error: "codes array required" }, 400);
    }
    alwaysApproveCodes = body.codes;
    return jsonResponse({ status: "ok" });
  }

  // ── Twilio Verify API ────────────────────────────────────────────────────

  // Match: /v2/Service/{serviceSID}/Verifications
  const verificationsMatch = path.match(/^\/v2\/Service\/([^/]+)\/Verifications$/);
  if (verificationsMatch && req.method === "POST") {
    await maybeLatency(cfg.latency);
    if (await maybeFail(cfg.failRate)) {
      return jsonResponse({ status: 500, message: "Simulated server error", code: 20001 }, 500);
    }

    const creds = parseBasicAuth(req.headers.get("authorization"));
    if (!creds || creds.user !== cfg.accountSid || creds.pass !== cfg.authToken) {
      return jsonResponse({ status: 401, message: "Invalid credentials", code: 20003 }, 401);
    }

    const body = await req.json();
    const phone: string = body.To || "";
    if (!phone) {
      return jsonResponse({ status: 400, message: "Missing 'To' parameter", code: 20005 }, 400);
    }

    const code = generateCode();
    store[phone] = { code, createdAt: Date.now(), verified: false };

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

  // Match: /v2/Service/{serviceSID}/VerificationCheck
  const checkMatch = path.match(/^\/v2\/Service\/([^/]+)\/VerificationCheck$/);
  if (checkMatch && req.method === "POST") {
    await maybeLatency(cfg.latency);
    if (await maybeFail(cfg.failRate)) {
      return jsonResponse({ status: 500, message: "Simulated server error", code: 20001 }, 500);
    }

    const creds = parseBasicAuth(req.headers.get("authorization"));
    if (!creds || creds.user !== cfg.accountSid || creds.pass !== cfg.authToken) {
      return jsonResponse({ status: 401, message: "Invalid credentials", code: 20003 }, 401);
    }

    const body = await req.json();
    const phone: string = body.To || "";
    const code: string = body.Code || "";

    if (!phone || !code) {
      return jsonResponse({ status: 400, message: "Missing 'To' or 'Code'", code: 20005 }, 400);
    }

    const state = store[phone];
    const isApproved = (state && state.code === code) || alwaysApproveCodes.includes(code);

    if (isApproved && state) {
      state.verified = true;
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

const cfg = parseFlags();
const startTime = Date.now();
alwaysApproveCodes = cfg.alwaysApprove.split(",").map((s: string) => s.trim());

console.error(`[mock-twilio] Starting on port ${cfg.port}`);
console.error(`[mock-twilio] Always-approve codes: ${alwaysApproveCodes.join(", ")}`);
console.error(`[mock-twilio] Account SID: ${cfg.accountSid}`);
if (cfg.latency > 0) console.error(`[mock-twilio] Simulated latency: ${cfg.latency}ms`);
if (cfg.failRate > 0) console.error(`[mock-twilio] Simulated fail rate: ${cfg.failRate}`);

Deno.serve({ port: cfg.port, hostname: "127.0.0.1" }, (req) => handleRequest(req, cfg));

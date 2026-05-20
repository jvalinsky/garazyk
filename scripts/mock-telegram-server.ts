#!/usr/bin/env -S deno run -A
import { parseArgs } from "@std/cli/parse-args";

interface VerificationState {
  phone: string;
  code: string;
  createdAt: number;
  verified: boolean;
}

interface RequestStore {
  [requestId: string]: VerificationState;
}

const store: RequestStore = {};
let alwaysApproveCodes: string[] = ["000000"];
const startTime = Date.now();

function parseFlags() {
  const args = parseArgs(Deno.args, { string: ["always-approve", "token"] });
  return {
    port: parseInt(String(args.port ?? Deno.env.get("PORT") ?? "8082"), 10),
    token: String(args.token ?? Deno.env.get("TELEGRAM_GATEWAY_TOKEN") ?? "TG_MOCK_TOKEN"),
    alwaysApprove: String(args["always-approve"] ?? Deno.env.get("ALWAYS_APPROVE_CODES") ?? "000000"),
    latency: parseInt(String(args.latency ?? Deno.env.get("LATENCY_MS") ?? "0"), 10),
    failRate: parseFloat(String(args["fail-rate"] ?? Deno.env.get("FAIL_RATE") ?? "0")),
  };
}

const cfg = parseFlags();
alwaysApproveCodes = cfg.alwaysApprove.split(",").map((s) => s.trim());

function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function randomRequestId(): string {
  return "req_" + Math.random().toString(36).substring(2, 15);
}

function parseBearerAuth(authHeader: string | null): string | null {
  if (!authHeader || !authHeader.startsWith("Bearer ")) return null;
  return authHeader.slice(7);
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

function createRequestStatus(requestId: string, phone: string, status: string = "pending") {
  return {
    request_id: requestId,
    phone_number: phone,
    request_cost: 0.0,
    delivery_status: { status: "sent", updated_at: Math.floor(Date.now() / 1000) },
    verification_status: { status, updated_at: Math.floor(Date.now() / 1000) },
  };
}

async function handleRequest(req: Request): Promise<Response> {
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
    if (!body.phone || !body.code || !body.requestId) {
      return jsonResponse({ error: "phone, code, and requestId required" }, 400);
    }
    store[body.requestId] = { phone: body.phone, code: body.code, createdAt: Date.now(), verified: false };
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

  // ── Telegram Gateway API ──────────────────────────────────────────────────

  await maybeLatency(cfg.latency);
  if (await maybeFail(cfg.failRate)) {
    return jsonResponse({ ok: false, error: "Simulated server error" }, 500);
  }

  const token = parseBearerAuth(req.headers.get("authorization"));
  if (!token || token !== cfg.token) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }

  if (path === "/checkSendAbility" && req.method === "POST") {
    const body = await req.json();
    const phone = body.phone_number;
    if (!phone) {
      return jsonResponse({ ok: false, error: "phone_number required" }, 400);
    }
    const requestId = randomRequestId();
    console.error(`[mock-telegram] checkSendAbility: ${phone} -> ${requestId}`);
    return jsonResponse({
      ok: true,
      result: createRequestStatus(requestId, phone),
    });
  }

  if (path === "/sendVerificationMessage" && req.method === "POST") {
    const body = await req.json();
    const phone = body.phone_number;
    if (!phone) {
      return jsonResponse({ ok: false, error: "phone_number required" }, 400);
    }
    const requestId = body.request_id || randomRequestId();
    const code = generateCode();
    store[requestId] = { phone, code, createdAt: Date.now(), verified: false };
    console.error(`[mock-telegram] sendVerificationMessage: ${phone} (${requestId}) -> code=${code}`);
    return jsonResponse({
      ok: true,
      result: createRequestStatus(requestId, phone),
    });
  }

  if (path === "/checkVerificationStatus" && req.method === "POST") {
    const body = await req.json();
    const requestId = body.request_id;
    const code = body.code;
    if (!requestId) {
      return jsonResponse({ ok: false, error: "request_id required" }, 400);
    }

    const state = store[requestId];
    const isApproved = (state && state.code === code) || alwaysApproveCodes.includes(code);

    if (isApproved && state) {
      state.verified = true;
    }

    console.error(
      `[mock-telegram] checkVerificationStatus: requestId=${requestId} code=${code} -> ${
        isApproved ? "approved" : "pending"
      }`,
    );

    return jsonResponse({
      ok: true,
      result: createRequestStatus(requestId, state?.phone || "unknown", isApproved ? "code_valid" : "code_invalid"),
    });
  }

  // ── 404 ──────────────────────────────────────────────────────────────────
  return jsonResponse({ ok: false, error: "Not found", path }, 404);
}

console.error(`[mock-telegram] Starting on port ${cfg.port}`);
console.error(`[mock-telegram] Always-approve codes: ${alwaysApproveCodes.join(", ")}`);
if (cfg.latency > 0) console.error(`[mock-telegram] Simulated latency: ${cfg.latency}ms`);
if (cfg.failRate > 0) console.error(`[mock-telegram] Simulated fail rate: ${cfg.failRate}`);

Deno.serve({ port: cfg.port, hostname: "127.0.0.1" }, (req) => handleRequest(req));

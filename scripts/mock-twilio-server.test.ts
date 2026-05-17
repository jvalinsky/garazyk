import { assertEquals, assertExists, assertNotEquals } from "@std/assert";

const PORT = 8099;
const SID = "AC00000000000000000000000000000000";
const TOKEN = "SK00000000000000000000000000000000";
const BASE = `http://127.0.0.1:${PORT}`;
const SERVICE_PATH = "/v2/Service/VA00000000000000000000000000000000";

function auth(): string {
  return `Basic ${btoa(`${SID}:${TOKEN}`)}`;
}

async function jsonRes(path: string, opts: RequestInit = {}): Promise<any> {
  const res = await fetch(`${BASE}${path}`, opts);
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 200)}`);
  return JSON.parse(text);
}

Deno.test("Mock Twilio server integration", async (t) => {
  let proc: Deno.ChildProcess | null = null;

  // ── Start server ───────────────────────────────────────────────────────────
  await t.step("start mock server", async () => {
    const cmd = new Deno.Command("deno", {
      args: [
        "run",
        "-A",
        "--config",
        "scripts/deno.json",
        "scripts/mock-twilio-server.ts",
        `--port=${PORT}`,
        "--always-approve=000000",
      ],
      cwd: Deno.cwd(),
      stdout: "null",
      stderr: "inherit",
    });
    proc = cmd.spawn();
    for (let i = 0; i < 30; i++) {
      try {
        const r = await (await fetch(`${BASE}/__control/health`)).json();
        if (r.status === "ok") break;
      } catch { /* retry */ }
      await new Promise((r) => setTimeout(r, 200));
    }
    const r = await jsonRes("/__control/health");
    assertEquals(r.status, "ok");
  });

  // ── Control API ────────────────────────────────────────────────────────────
  await t.step("GET /__control/health returns ok", async () => {
    const r = await jsonRes("/__control/health");
    assertEquals(r.status, "ok");
    assertNotEquals(r.uptime, undefined);
  });

  await t.step("GET /__control/state returns empty store initially", async () => {
    const r = await jsonRes("/__control/state");
    assertEquals(r.store, {});
    assertEquals(r.alwaysApproveCodes, ["000000"]);
  });

  await t.step("POST /__control/setCode stores a verification code", async () => {
    await jsonRes("/__control/setCode", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "+1555control", code: "555555" }),
    });
    const state = await jsonRes("/__control/state");
    assertEquals(state.store["+1555control"].code, "555555");
    assertEquals(state.store["+1555control"].verified, false);
  });

  await t.step("POST /__control/setCode rejects missing phone", async () => {
    const res = await fetch(`${BASE}/__control/setCode`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: "123" }),
    });
    assertEquals(res.status, 400);
    await res.body?.cancel();
  });

  await t.step("POST /__control/setAlwaysApprove replaces codes list", async () => {
    await jsonRes("/__control/setAlwaysApprove", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ codes: ["alpha", "beta"] }),
    });
    const state = await jsonRes("/__control/state");
    assertEquals(state.alwaysApproveCodes, ["alpha", "beta"]);
  });

  await t.step("POST /__control/reset clears all state", async () => {
    await jsonRes("/__control/setCode", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "+1555temp", code: "111111" }),
    });
    await jsonRes("/__control/reset", { method: "POST" });
    const state = await jsonRes("/__control/state");
    assertEquals(state.store, {});
    assertEquals(state.alwaysApproveCodes, ["000000"]); // reset restores default
  });

  // ── Twilio Verify API — Verifications ──────────────────────────────────────
  await t.step("POST /Verifications returns pending with sid", async () => {
    const r = await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555send", Channel: "sms" }),
    });
    assertEquals(r.status, "pending");
    assertExists(r.sid);
    assertEquals(r.to, "+1555send");
    assertEquals(r.channel, "sms");
    assertEquals(r.valid, false);
  });

  await t.step("POST /Verifications stores generated code in state", async () => {
    const r = await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555store", Channel: "sms" }),
    });
    const state = await jsonRes("/__control/state");
    const entry = state.store[r.to];
    assertExists(entry, "No entry in store for phone");
    assertEquals(typeof entry.code, "string");
    assertEquals(entry.code.length, 6, "Code should be 6 digits");
    assertEquals(entry.verified, false);
  });

  await t.step("POST /Verifications rejects missing To", async () => {
    const res = await fetch(`${BASE}${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ Channel: "sms" }),
    });
    assertEquals(res.status, 400);
    await res.body?.cancel();
  });

  // ── Twilio Verify API — VerificationCheck ──────────────────────────────────
  await t.step("POST /VerificationCheck with correct code returns approved", async () => {
    await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555check1", Channel: "sms" }),
    });
    const state = await jsonRes("/__control/state");
    const code = state.store["+1555check1"].code;

    const r = await jsonRes(`${SERVICE_PATH}/VerificationCheck`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555check1", Code: code }),
    });
    assertEquals(r.status, "approved");
    assertEquals(r.valid, true);
    assertEquals(r.to, "+1555check1");
  });

  await t.step("VerificationCheck marks state as verified", async () => {
    await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555check2", Channel: "sms" }),
    });
    const before = await jsonRes("/__control/state");
    const code = before.store["+1555check2"].code;

    await jsonRes(`${SERVICE_PATH}/VerificationCheck`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555check2", Code: code }),
    });
    const after = await jsonRes("/__control/state");
    assertEquals(after.store["+1555check2"].verified, true);
  });

  await t.step("POST /VerificationCheck with wrong code returns pending", async () => {
    await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555wrong", Channel: "sms" }),
    });
    const r = await jsonRes(`${SERVICE_PATH}/VerificationCheck`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555wrong", Code: "999999" }),
    });
    assertEquals(r.status, "pending");
    assertEquals(r.valid, false);
  });

  await t.step("Always-approve code 000000 returns approved", async () => {
    const r = await jsonRes(`${SERVICE_PATH}/VerificationCheck`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555always", Code: "000000" }),
    });
    assertEquals(r.status, "approved");
    assertEquals(r.valid, true);
  });

  await t.step("Dynamic always-approve code works", async () => {
    await jsonRes("/__control/setAlwaysApprove", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ codes: ["000000", "debug"] }),
    });
    const r = await jsonRes(`${SERVICE_PATH}/VerificationCheck`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555dynamic", Code: "debug" }),
    });
    assertEquals(r.status, "approved");
    assertEquals(r.valid, true);
  });

  await t.step("Always-approve code does NOT create store entry", async () => {
    const r = await jsonRes(`${SERVICE_PATH}/VerificationCheck`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555noverify", Code: "000000" }),
    });
    assertEquals(r.status, "approved");
    const state = await jsonRes("/__control/state");
    assertEquals(state.store["+1555noverify"], undefined);
  });

  // ── Auth ───────────────────────────────────────────────────────────────────
  await t.step("Missing auth header returns 401", async () => {
    const res = await fetch(`${BASE}${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ To: "+1555" }),
    });
    assertEquals(res.status, 401);
    await res.body?.cancel();
  });

  await t.step("Bad auth returns 401", async () => {
    const res = await fetch(`${BASE}${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Basic " + btoa("BAD:CREDS") },
      body: JSON.stringify({ To: "+1555" }),
    });
    assertEquals(res.status, 401);
    await res.body?.cancel();
  });

  // ── Edge cases ─────────────────────────────────────────────────────────────
  await t.step("Unknown path returns 404", async () => {
    const res = await fetch(`${BASE}/nonexistent`);
    assertEquals(res.status, 404);
    await res.body?.cancel();
  });

  await t.step("Sequential sends generate different codes", async () => {
    await jsonRes("/__control/reset", { method: "POST" });
    await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555seq1", Channel: "sms" }),
    });
    const s1 = await jsonRes("/__control/state");
    const c1 = s1.store["+1555seq1"].code;

    await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555seq2", Channel: "sms" }),
    });
    const s2 = await jsonRes("/__control/state");
    const c2 = s2.store["+1555seq2"].code;

    assertNotEquals(c1, c2, "Each send should generate a unique code");
  });

  await t.step("Re-sending to same phone overwrites code", async () => {
    await jsonRes("/__control/reset", { method: "POST" });
    await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555dup", Channel: "sms" }),
    });
    const s1 = await jsonRes("/__control/state");
    const c1 = s1.store["+1555dup"].code;

    await jsonRes(`${SERVICE_PATH}/Verifications`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ To: "+1555dup", Channel: "sms" }),
    });
    const s2 = await jsonRes("/__control/state");
    const c2 = s2.store["+1555dup"].code;

    assertNotEquals(c1, c2, "Re-sending should generate a new code");
  });

  // ── Teardown ───────────────────────────────────────────────────────────────
  await t.step("stop mock server", async () => {
    if (proc) {
      try {
        proc.kill("SIGTERM");
      } catch { /* ignore */ }
      proc = null;
    }
    await new Promise((r) => setTimeout(r, 300));
    // Verify it's dead
    try {
      const r = await fetch(`${BASE}/__control/health`);
      await r.body?.cancel();
      throw new Error("Server still running after kill");
    } catch {
      // Expected — connection refused
    }
  });
});

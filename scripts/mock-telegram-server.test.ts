import { assertEquals, assertExists, assertNotEquals } from "@std/assert";

const TOKEN = "TG_MOCK_TOKEN";
let base = "";

function auth(): string {
  return `Bearer ${TOKEN}`;
}

async function jsonRes(path: string, opts: RequestInit = {}): Promise<any> {
  const res = await fetch(`${base}${path}`, opts);
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 200)}`);
  return JSON.parse(text);
}

Deno.test("Mock Telegram server integration", async (t) => {
  let proc: Deno.ChildProcess | null = null;
  const portFile = await Deno.makeTempFile({
    prefix: "mock-telegram-",
    suffix: ".url",
  });

  // ── Start server ───────────────────────────────────────────────────────────
  await t.step("start mock server", async () => {
    const cmd = new Deno.Command("deno", {
      args: [
        "run",
        "-A",
        "--config",
        "deno.json",
        "scripts/mock-telegram-server.ts",
        "--port=0",
        `--port-file=${portFile}`,
        `--token=${TOKEN}`,
      ],
      cwd: Deno.cwd(),
      stdout: "null",
      stderr: "inherit",
    });
    proc = cmd.spawn();
    for (let i = 0; i < 30; i++) {
      try {
        base = (await Deno.readTextFile(portFile)).trim();
        const r = await (await fetch(`${base}/__control/health`)).json();
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

  await t.step("GET /__control/state returns initial state", async () => {
    const r = await jsonRes("/__control/state");
    assertEquals(r.store, {});
    assertEquals(r.alwaysApproveCodes, ["000000"]);
  });

  await t.step("POST /__control/setCode stores a code", async () => {
    await jsonRes("/__control/setCode", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        phone: "+1555",
        code: "123456",
        requestId: "test_req",
      }),
    });
    const state = await jsonRes("/__control/state");
    assertEquals(state.store["test_req"].code, "123456");
  });

  // ── Telegram Gateway API ──────────────────────────────────────────────────
  await t.step("POST /checkSendAbility returns a requestId", async () => {
    const r = await jsonRes("/checkSendAbility", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ phone_number: "+1555" }),
    });
    assertEquals(r.ok, true);
    assertExists(r.result.request_id);
    assertEquals(r.result.phone_number, "+1555");
  });

  await t.step("POST /sendVerificationMessage stores code", async () => {
    const r = await jsonRes("/sendVerificationMessage", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ phone_number: "+1555" }),
    });
    assertEquals(r.ok, true);
    const requestId = r.result.request_id;
    const state = await jsonRes("/__control/state");
    assertExists(state.store[requestId]);
    assertEquals(state.store[requestId].phone, "+1555");
    assertEquals(state.store[requestId].code.length, 6);
  });

  await t.step("POST /checkVerificationStatus with correct code", async () => {
    const r1 = await jsonRes("/sendVerificationMessage", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ phone_number: "+1555check" }),
    });
    const requestId = r1.result.request_id;
    const state = await jsonRes("/__control/state");
    const code = state.store[requestId].code;

    const r2 = await jsonRes("/checkVerificationStatus", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ request_id: requestId, code: code }),
    });
    assertEquals(r2.ok, true);
    assertEquals(r2.result.verification_status.status, "code_valid");
  });

  await t.step("POST /checkVerificationStatus with wrong code", async () => {
    const r1 = await jsonRes("/sendVerificationMessage", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ phone_number: "+1555wrong" }),
    });
    const requestId = r1.result.request_id;

    const r2 = await jsonRes("/checkVerificationStatus", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ request_id: requestId, code: "999999" }),
    });
    assertEquals(r2.ok, true);
    assertEquals(r2.result.verification_status.status, "code_invalid");
  });

  await t.step("Always-approve code works", async () => {
    const r = await jsonRes("/checkVerificationStatus", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: auth() },
      body: JSON.stringify({ request_id: "any", code: "000000" }),
    });
    assertEquals(r.ok, true);
    assertEquals(r.result.verification_status.status, "code_valid");
  });

  // ── Auth ──────────────────────────────────────────────────────────────────
  await t.step("Missing auth returns 401", async () => {
    const res = await fetch(`${base}/checkSendAbility`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone_number: "+1555" }),
    });
    assertEquals(res.status, 401);
    await res.body?.cancel();
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
    await Deno.remove(portFile).catch(() => {});
  });
});

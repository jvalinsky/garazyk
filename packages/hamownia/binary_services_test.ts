import { assertEquals } from "@std/assert";
import type { TopologyRunContext } from "@garazyk/schemat/runtime";
import {
  type BinaryServiceName,
  defaultBinaryServices,
  getBinaryServiceStatus,
  resolveBinaryServiceStartPlan,
} from "./binary_services.ts";

Deno.test("binary services default to PLC, PDS, Relay, and AppView", () => {
  assertEquals(defaultBinaryServices(), ["plc", "pds", "relay", "appview"]);
});

Deno.test("binary service start plan applies per-service args and env overrides", async () => {
  const plan = await resolveBinaryServiceStartPlan({
    name: "pds",
    root: "/repo",
    dataRoot: "/run/data",
    commonEnv: {
      PDS_RUNNING_TESTS: "true",
      PDS_ADMIN_PASSWORD: "default-password",
    },
    options: {
      args: {
        pds: ["serve", "--config", "/tmp/pds.json"],
      },
      env: {
        pds: {
          PDS_ADMIN_PASSWORD: "override-password",
          PDS_CUSTOM_FLAG: "1",
        },
      },
    },
  });

  assertEquals(plan.name, "pds");
  assertEquals(plan.port, 2583);
  assertEquals(plan.dataDir, "/run/data/pds");
  assertEquals(plan.args, ["serve", "--config", "/tmp/pds.json"]);
  assertEquals(plan.env.PDS_RUNNING_TESTS, "true");
  assertEquals(plan.env.PDS_ADMIN_PASSWORD, "override-password");
  assertEquals(plan.env.PDS_CUSTOM_FLAG, "1");
});

Deno.test("binary service status parses PID file with typed deterministic probes", async () => {
  const dir = await Deno.makeTempDir();
  const pidFile = `${dir}/services.pid`;
  await Deno.writeTextFile(
    pidFile,
    [
      "# test PIDs",
      "PDS_PID=42",
      "APPVIEW_PID=43",
      "IGNORED=value",
      "",
    ].join("\n"),
  );

  const fetched: Array<{ url: string; authorization?: string }> = [];
  const ctx: TopologyRunContext = {
    runId: "test",
    runDir: dir,
    diagnosticsDir: `${dir}/diagnostics`,
    logDir: `${dir}/logs`,
    pidFile,
    composeProject: "garazyk-test",
    baseDir: dir,
  };

  try {
    const status: Record<
      BinaryServiceName,
      { running: boolean; pid?: number; healthy?: boolean }
    > = await getBinaryServiceStatus(ctx, {
      isProcessRunning: (pid) => pid === 42,
      fetchHealth: (input, init) => {
        const requestInit = init as { headers?: HeadersInit } | undefined;
        const headers = requestInit?.headers instanceof Headers
          ? requestInit.headers
          : new Headers(requestInit?.headers);
        fetched.push({
          url: String(input),
          authorization: headers.get("Authorization") ?? undefined,
        });
        return Promise.resolve(new Response("ok", { status: 200 }));
      },
    });

    assertEquals(status.pds, { running: true, pid: 42, healthy: true });
    assertEquals(status.appview, { running: false, pid: 43, healthy: false });
    assertEquals(status.plc.running, false);
    assertEquals(fetched, [{
      url: "http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer",
      authorization: undefined,
    }]);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

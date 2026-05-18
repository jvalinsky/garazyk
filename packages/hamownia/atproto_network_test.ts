import { assertEquals } from "@std/assert";
import type { TopologyRunContext } from "@garazyk/schemat/runtime";
import {
  applyTopologyEnvironment,
  startLocalNetwork,
  topologyManifestPath,
} from "./atproto_network.ts";
import type { StartBinaryOptions } from "./binary_services.ts";

Deno.test("topology mode records topology name and manifest path in env", () => {
  const oldTopology = Deno.env.get("ATPROTO_TOPOLOGY");
  const oldManifest = Deno.env.get("ATPROTO_TOPOLOGY_MANIFEST");

  try {
    applyTopologyEnvironment("garazyk-default", "/tmp/topology-manifest.json");

    assertEquals(Deno.env.get("ATPROTO_TOPOLOGY"), "garazyk-default");
    assertEquals(
      Deno.env.get("ATPROTO_TOPOLOGY_MANIFEST"),
      "/tmp/topology-manifest.json",
    );
  } finally {
    restoreEnv("ATPROTO_TOPOLOGY", oldTopology);
    restoreEnv("ATPROTO_TOPOLOGY_MANIFEST", oldManifest);
  }
});

Deno.test("topology manifest path stays inside run directory", () => {
  const ctx: TopologyRunContext = {
    runId: "test",
    runDir: "/tmp/garazyk-run",
    diagnosticsDir: "/tmp/garazyk-run/diagnostics",
    logDir: "/tmp/garazyk-run/logs",
    pidFile: "/tmp/garazyk-run/pids.txt",
    composeProject: "garazyk-test",
    baseDir: "/tmp",
  };

  assertEquals(
    topologyManifestPath(ctx),
    "/tmp/garazyk-run/topology-manifest.json",
  );
});

Deno.test("binary mode starts binary services with default options", async () => {
  const dir = await Deno.makeTempDir({ prefix: "hamownia-binary-network-" });
  const ctx: TopologyRunContext = {
    runId: "binary-test",
    runDir: dir,
    diagnosticsDir: `${dir}/diagnostics`,
    logDir: `${dir}/logs`,
    pidFile: `${dir}/pids.txt`,
    composeProject: "garazyk-binary-test",
    baseDir: dir,
  };
  const calls: Array<
    { ctx: TopologyRunContext; options?: StartBinaryOptions }
  > = [];

  try {
    await startLocalNetwork({ useBinary: true }, {
      initRunDir: () => ctx,
      startBinaryServices: (runCtx, options) => {
        calls.push({ ctx: runCtx, options });
        return Promise.resolve();
      },
    });

    assertEquals(calls.length, 1);
    assertEquals(calls[0].ctx, ctx);
    assertEquals(calls[0].options, undefined);
    assertEquals(
      await Deno.readTextFile(`${dir}/latest-scenario-run-id`),
      "binary-test",
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    Deno.env.delete(name);
  } else {
    Deno.env.set(name, value);
  }
}

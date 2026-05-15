import { assertEquals } from "jsr:@std/assert";
import { basename } from "@std/path";
import { composeFilesForOptions, createNetworkSession } from "./docker.ts";
import { initRunDir } from "./docker_config.ts";

function resetRunEnv() {
  for (
    const key of [
      "ATPROTO_E2E_RUN_ID",
      "ATPROTO_E2E_BASE_DIR",
      "ATPROTO_E2E_RUN_DIR",
      "ATPROTO_E2E_DIAGNOSTICS_DIR",
      "ATPROTO_E2E_LOG_DIR",
      "ATPROTO_E2E_PID_FILE",
      "ATPROTO_E2E_COMPOSE_PROJECT",
    ]
  ) {
    Deno.env.delete(key);
  }
}

Deno.test("createNetworkSession preserves explicit compose context", () => {
  resetRunEnv();
  const ctx = initRunDir("session-context-default");
  const session = createNetworkSession(ctx, {
    composeFiles: ["/repo/docker/local-network/docker-compose.yml"],
    withPds2: false,
    useBinary: false,
  });

  assertEquals(session.runId, "session-context-default");
  assertEquals(session.composeProject, "garazyk-e2e-session-context-default");
  assertEquals(session.composeFiles, ["/repo/docker/local-network/docker-compose.yml"]);
  assertEquals(session.withPds2, false);
});

Deno.test("composeFilesForOptions uses base compose file for default stack", async () => {
  resetRunEnv();
  const ctx = initRunDir("compose-default");
  const composeFiles = await composeFilesForOptions(ctx, {});

  assertEquals(composeFiles.map((path) => basename(path)), ["docker-compose.yml"]);
});

Deno.test("composeFilesForOptions includes scenarios compose file for PDS2 stack", async () => {
  resetRunEnv();
  const ctx = initRunDir("compose-pds2");
  const composeFiles = await composeFilesForOptions(ctx, { withPds2: true });

  assertEquals(composeFiles.map((path) => basename(path)), [
    "docker-compose.yml",
    "docker-compose.scenarios.yml",
  ]);
});

Deno.test("composeFilesForOptions resolves generated topology compose from run directory", async () => {
  resetRunEnv();
  const ctx = initRunDir("compose-topology");
  const topologyCompose = `${ctx.runDir}/docker-compose.topology.yml`;
  await Deno.writeTextFile(topologyCompose, "services: {}\n");

  const composeFiles = await composeFilesForOptions(ctx, { topology: "garazyk-default" });

  assertEquals(composeFiles, [topologyCompose]);
});

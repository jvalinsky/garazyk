#!/usr/bin/env -S deno run -A
/**
 * manage_local_network.ts — Deno-native replacement for setup_local_network.sh
 *
 * Usage:
 *   deno run -A scripts/manage_local_network.ts              # Start stack
 *   deno run -A scripts/manage_local_network.ts --binary    # Start from build/bin/
 *   deno run -A scripts/manage_local_network.ts --pds2      # Also start second PDS
 *   deno run -A scripts/manage_local_network.ts --wait-only # Just wait for healthy
 *   deno run -A scripts/manage_local_network.ts --teardown  # Stop all services
 *   deno run -A scripts/manage_local_network.ts --otel      # Enable OpenTelemetry
 */

import { parseArgs } from "@std/cli";
import {
  collectDiagnostics,
  initRunDir,
  type LocalNetworkOptions,
  startLocalNetwork,
  stopLocalNetwork,
} from "../packages/hamownia/atproto_network.ts";
import { initE2eTracing } from "../packages/hamownia/otel.ts";

const args = parseArgs(Deno.args, {
  boolean: [
    "binary",
    "pds2",
    "with-phone-verification",
    "otel",
    "wait-only",
    "teardown",
    "keep-running",
    "collect-diagnostics",
    "skip-docker-stage",
    "allow-hybrid-network",
    "help",
  ],
  string: [
    "web-client",
    "client-flow",
    "topology",
    "run-id",
    "diagnostics-dir",
  ],
  alias: { h: "help" },
});

if (args.help) {
  console.log(`Usage: manage_local_network.ts [options]

  --binary                 Start services from build/bin/ (no Docker)
  --pds2                   Also start a second PDS on port 2587
  --with-phone-verification Start mock Twilio server
  --otel                   Enable OpenTelemetry tracing (SigNoz on port 3301)
  --web-client PRESET      Add a generated web-client compose service
  --client-flow FLOW       Browser flow name for metadata
  --allow-hybrid-network   Allow browser flows to call public hosts
  --topology PRESET        Use a topology preset
  --wait-only              Don't start services, just wait for healthy
  --teardown               Stop services for this run
  --keep-running           Leave services running after setup
  --collect-diagnostics    Capture health, logs, and compose state
  --skip-docker-stage      Reuse existing staged Docker binaries
  --run-id ID              Reuse or name the shared e2e run directory
  --diagnostics-dir DIR    Write diagnostics to DIR`);
  Deno.exit(0);
}

if (args.otel) {
  initE2eTracing("garazyk-manage-network");
}

const opts: LocalNetworkOptions = {
  useBinary: args.binary,
  withPds2: args.pds2,
  keepRunning: args["keep-running"],
  waitOnly: args["wait-only"],
  skipDockerStage: args["skip-docker-stage"],
  runId: args["run-id"],
  diagnosticsDir: args["diagnostics-dir"],
  webClient: args["web-client"],
  clientFlow: args["client-flow"],
  allowHybridNetwork: args["allow-hybrid-network"],
  topology: args.topology,
};

try {
  if (args.teardown) {
    await stopLocalNetwork({
      ...opts,
      collectDiagnostics: args["collect-diagnostics"],
    });
  } else if (args["collect-diagnostics"] && !args.teardown) {
    const ctx = initRunDir(opts.runId);
    await collectDiagnostics(ctx);
  } else {
    await startLocalNetwork(opts);
  }
} catch (err) {
  console.error(`[ERROR] ${(err as Error).message}`);
  Deno.exit(1);
}

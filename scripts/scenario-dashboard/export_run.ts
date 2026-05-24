/**
 * Export a run replay bundle (standalone HTML + copied artifacts).
 *
 * Usage:
 *   deno run -A scripts/scenario-dashboard/export_run.ts <runId>
 *
 * @module export_run
 */

import { db } from "./db/index.ts";
import { exportRunBundle } from "./lib/export_run_lib.ts";

const runId = Deno.args[0];
if (!runId) {
  console.error("Usage: deno run -A export_run.ts <runId>");
  Deno.exit(1);
}

try {
  const { indexPath } = await exportRunBundle(db, runId);
  console.log(`Exported replay bundle to ${indexPath}`);
} catch (e) {
  console.error((e as Error).message);
  Deno.exit(1);
}

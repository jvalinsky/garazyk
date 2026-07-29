#!/usr/bin/env -S deno run -A
/**
 * Compatibility entry point for the repository documentation CLI.
 *
 * Use the workspace Deno configuration when running this script directly:
 * `deno run -A --config=deno.json scripts/docs/repo_docs.ts …`.
 */
import { main } from "../../packages/narzedzia/repo_docs.ts";

export { main };

if (import.meta.main) {
  Deno.exit(await main());
}

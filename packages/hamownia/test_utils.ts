/**
 * Shared test utilities for hamownia CLI integration tests.
 *
 * Used by both packages/hamownia/agent_test.ts and
 * .pi/extensions/garazyk-tools/test.ts to avoid duplicating
 * subprocess-spawn logic.
 *
 * All functions use Deno APIs and require --allow-run and --allow-env.
 */

/** CLI entry point relative to the repo root. */
export const CLI_PATH = "packages/hamownia/cli.ts";

/** Return type for spawn functions. */
export interface SpawnResult {
  stdout: string;
  stderr: string;
  code: number;
}

/**
 * Spawn the hamownia CLI with sub-args (after the deno run prefix).
 *
 * Example: spawnCli(["agent", "list"]) runs
 *   deno run -A packages/hamownia/cli.ts agent list
 */
export async function spawnCli(
  args: string[],
): Promise<SpawnResult> {
  const cmd = new Deno.Command("deno", {
    args: ["run", "--quiet", "-A", CLI_PATH, ...args],
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout, stderr } = await cmd.output();
  return {
    stdout: new TextDecoder().decode(stdout),
    stderr: new TextDecoder().decode(stderr),
    code,
  };
}

/**
 * Spawn the hamownia CLI with a timeout via AbortController.
 *
 * Uses Deno.Command's signal option to abort after timeoutMs.
 * Defaults to 30s — override for slow scenario runs.
 *
 * If the timeout fires, the returned promise rejects with AbortError.
 */
export async function spawnCliWithTimeout(
  args: string[],
  timeoutMs = 30_000,
): Promise<SpawnResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const cmd = new Deno.Command("deno", {
      args: ["run", "--quiet", "-A", CLI_PATH, ...args],
      stdout: "piped",
      stderr: "piped",
      signal: controller.signal,
    });
    const { code, stdout, stderr } = await cmd.output();
    return {
      stdout: new TextDecoder().decode(stdout),
      stderr: new TextDecoder().decode(stderr),
      code,
    };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Check whether Docker is available by running `docker info`.
 *
 * Call this before Docker-dependent integration tests to
 * gracefully skip when Docker is not installed or not running.
 */
export async function dockerAvailable(): Promise<boolean> {
  try {
    const cmd = new Deno.Command("docker", {
      args: ["info"],
      stdout: "null",
      stderr: "null",
    });
    const { code } = await cmd.output();
    return code === 0;
  } catch {
    return false;
  }
}

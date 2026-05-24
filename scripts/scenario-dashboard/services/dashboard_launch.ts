/** Detect whether the dashboard process was started for agent-driven use. @module dashboard_launch */

const TRUTHY = new Set(["1", "true", "yes", "on"]);

function envTruthy(name: string): boolean {
  const value = Deno.env.get(name);
  return value !== undefined && TRUTHY.has(value.toLowerCase());
}

/**
 * True when the dev/production server was launched with an agent flag.
 *
 * Set `GARAZYK_DASHBOARD_AGENT_LAUNCH=1` when starting the server from an
 * automation (Cursor agent, CI, etc.).
 */
export function isAgentLaunchFromEnv(): boolean {
  return envTruthy("GARAZYK_DASHBOARD_AGENT_LAUNCH") ||
    envTruthy("CURSOR_AGENT");
}

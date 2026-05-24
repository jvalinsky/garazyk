/** Browser-side launch hints for agent-driven dashboard sessions. @module client_launch */

const TRUTHY = new Set(["1", "true", "yes", "on"]);

/** True when the page URL requests an agent-driven dashboard session. */
export function readAgentLaunchFromUrl(
  search = typeof globalThis.location !== "undefined"
    ? globalThis.location.search
    : "",
): boolean {
  const params = new URLSearchParams(search);
  for (const key of ["agentLaunch", "agent"]) {
    const value = params.get(key);
    if (value !== null && TRUTHY.has(value.toLowerCase())) {
      return true;
    }
  }
  return false;
}

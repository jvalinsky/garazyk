/** Public network leak detection for browser-based E2E tests. @module browser_flow */
import type { Page } from "playwright";

const DEFAULT_BLOCKED_PUBLIC_HOSTS = [
  "bsky.app",
  "api.bsky.app",
  "bsky.network",
  "plc.directory",
];

/** Resolve the set of public hosts to block during tests. */
export function blockedPublicHosts(): string[] {
  const configured = Deno.env.get("ATPROTO_BLOCKED_PUBLIC_HOSTS");
  if (configured !== undefined) {
    return configured.split(",").map((host) => host.trim()).filter(Boolean);
  }
  return Deno.env.get("ATPROTO_ALLOW_HYBRID_NETWORK") === "1"
    ? []
    : DEFAULT_BLOCKED_PUBLIC_HOSTS;
}

/** Attach a request interceptor to detect unwanted outbound calls to public hosts. */
export function attachPublicNetworkLeakGuard(page: Page): string[] {
  const blockedHosts = blockedPublicHosts();
  const leaks: string[] = [];
  if (blockedHosts.length === 0) return leaks;

  page.on("request", (request) => {
    let host = "";
    try {
      host = new URL(request.url()).hostname;
    } catch {
      return;
    }
    if (
      blockedHosts.some((blocked) =>
        host === blocked || host.endsWith(`.${blocked}`)
      )
    ) {
      leaks.push(request.url());
    }
  });
  return leaks;
}

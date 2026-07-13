/**
 * Request boundaries for the local scenario dashboard.
 *
 * The dashboard controls processes on the developer's machine, so its HTTP
 * mutations require a short-lived capability that is generated for each
 * server launch. A dashboard that is deliberately exposed beyond loopback
 * also requires an operator-supplied authentication token.
 *
 * @module services/dashboard_security
 */

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 3001;
const CAPABILITY_TTL_MS = 8 * 60 * 60 * 1000;
const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

/** Immutable security settings for one dashboard server launch. */
export interface DashboardSecurity {
  host: string;
  port: number;
  isLoopback: boolean;
  mutationCapability: string;
  capabilityExpiresAt: number;
  authenticationToken?: string;
}

/** Optional overrides used by tests and the process-level configuration. */
export interface DashboardSecurityOptions {
  host?: string;
  port?: number;
  authenticationToken?: string;
  capability?: string;
  expiresAt?: number;
  now?: number;
}

let configuredSecurity: DashboardSecurity | undefined;

/**
 * Build the request-security boundary for one dashboard process.
 *
 * `host` defaults to the IPv4 loopback address. Any non-loopback listener
 * must be explicitly named and given an authentication token.
 */
export function createDashboardSecurity(
  options: DashboardSecurityOptions = {},
): DashboardSecurity {
  const host = normalizeHost(options.host ?? DEFAULT_HOST);
  const port = validatePort(options.port ?? DEFAULT_PORT);
  const isLoopback = isLoopbackHost(host);
  const authenticationToken = normalizeToken(options.authenticationToken);

  if (!isLoopback && !authenticationToken) {
    throw new Error(
      "DASHBOARD_AUTH_TOKEN is required when DASHBOARD_HOST is not loopback",
    );
  }

  const now = options.now ?? Date.now();
  const capability = options.capability ?? createCapability();
  const expiresAt = options.expiresAt ?? now + CAPABILITY_TTL_MS;
  if (!Number.isFinite(expiresAt)) {
    throw new Error("Dashboard mutation capability expiration must be finite");
  }

  return Object.freeze({
    host,
    port,
    isLoopback,
    mutationCapability: capability,
    capabilityExpiresAt: expiresAt,
    authenticationToken,
  });
}

/**
 * Return the process-wide dashboard security boundary.
 *
 * Environment values are read once so that a capability cannot change during
 * a running dashboard session.
 */
export function getDashboardSecurity(): DashboardSecurity {
  if (!configuredSecurity) {
    configuredSecurity = createDashboardSecurity({
      host: Deno.env.get("DASHBOARD_HOST") ?? DEFAULT_HOST,
      port: parsePort(Deno.env.get("DASHBOARD_PORT")),
      authenticationToken: Deno.env.get("DASHBOARD_AUTH_TOKEN"),
    });
  }
  return configuredSecurity;
}

/**
 * Validate a request reaching the dashboard. Non-loopback servers require
 * authentication for all content; API mutations additionally require the
 * launch capability.
 */
export function validateDashboardRequest(
  request: Request,
  security: DashboardSecurity = getDashboardSecurity(),
  isMutation = false,
  now = Date.now(),
): Response | null {
  if (!isAllowedHostHeader(request.headers.get("host"), security)) {
    return forbidden();
  }

  if (!isAllowedOrigin(request.headers.get("origin"), security)) {
    return forbidden();
  }

  if (
    !security.isLoopback &&
    !sameSecret(
      readBearerToken(request.headers.get("authorization")),
      security.authenticationToken,
    )
  ) {
    return new Response(
      JSON.stringify({ error: "Dashboard authentication required" }),
      {
        status: 401,
        headers: {
          "Cache-Control": "no-store",
          "Content-Type": "application/json",
          "WWW-Authenticate": 'Bearer realm="Garazyk Scenario Dashboard"',
        },
      },
    );
  }

  if (!isMutation) return null;

  if (
    now >= security.capabilityExpiresAt ||
    !sameSecret(
      request.headers.get("x-dashboard-capability"),
      security.mutationCapability,
    )
  ) {
    return forbidden();
  }

  return null;
}

/** Validate a process, network, or run mutation. */
export function validateDashboardMutation(
  request: Request,
  security?: DashboardSecurity,
  now?: number,
): Response | null {
  return validateDashboardRequest(request, security, true, now);
}

function normalizeHost(value: string): string {
  const host = value.trim().toLowerCase();
  if (
    !host || host.includes("://") || host.includes("/") || host.includes("@")
  ) {
    throw new Error("DASHBOARD_HOST must be a hostname or IP address");
  }
  return host.replace(/^\[|\]$/g, "");
}

function validatePort(port: number): number {
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("DASHBOARD_PORT must be an integer from 1 through 65535");
  }
  return port;
}

function parsePort(value: string | undefined): number {
  if (value === undefined || value === "") return DEFAULT_PORT;
  if (!/^\d+$/.test(value)) {
    throw new Error("DASHBOARD_PORT must be an integer from 1 through 65535");
  }
  return validatePort(Number(value));
}

function normalizeToken(value: string | undefined): string | undefined {
  if (!value) return undefined;
  if (value.trim() !== value) {
    throw new Error(
      "DASHBOARD_AUTH_TOKEN must not contain leading or trailing whitespace",
    );
  }
  return value;
}

function isLoopbackHost(host: string): boolean {
  return LOOPBACK_HOSTS.has(host) || /^127(?:\.\d{1,3}){3}$/.test(host);
}

function createCapability(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function isAllowedHostHeader(
  hostHeader: string | null,
  security: DashboardSecurity,
): boolean {
  const authority = parseAuthority(hostHeader);
  if (!authority || authority.port !== security.port) return false;

  if (security.isLoopback) {
    return isLoopbackHost(authority.host);
  }
  return authority.host === security.host;
}

function isAllowedOrigin(
  originHeader: string | null,
  security: DashboardSecurity,
): boolean {
  // Non-browser dashboard clients have no Origin header. Their Host,
  // authentication, and mutation-capability checks still apply.
  if (originHeader === null) return true;

  let origin: URL;
  try {
    origin = new URL(originHeader);
  } catch {
    return false;
  }
  if (
    origin.origin !== originHeader ||
    (origin.protocol !== "http:" && origin.protocol !== "https:")
  ) {
    return false;
  }

  const host = origin.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  const port = origin.port === ""
    ? (origin.protocol === "https:" ? 443 : 80)
    : Number(origin.port);
  if (port !== security.port) return false;

  return security.isLoopback ? isLoopbackHost(host) : host === security.host;
}

function parseAuthority(
  value: string | null,
): { host: string; port: number } | null {
  if (!value || value.trim() !== value || value.includes(",")) return null;
  try {
    const url = new URL(`http://${value}`);
    if (
      url.username || url.password || url.pathname !== "/" || url.search ||
      url.hash
    ) {
      return null;
    }
    const port = url.port === "" ? 80 : Number(url.port);
    if (!Number.isInteger(port) || port < 1 || port > 65_535) return null;
    return {
      host: url.hostname.toLowerCase().replace(/^\[|\]$/g, ""),
      port,
    };
  } catch {
    return null;
  }
}

function readBearerToken(value: string | null): string | undefined {
  if (!value || !value.startsWith("Bearer ")) return undefined;
  const token = value.slice("Bearer ".length);
  return token && !/\s/.test(token) ? token : undefined;
}

/** Compare secret values without returning early on the first mismatch. */
function sameSecret(
  actual: string | null | undefined,
  expected: string | undefined,
): boolean {
  if (!actual || !expected) return false;

  const length = Math.max(actual.length, expected.length);
  let difference = actual.length ^ expected.length;
  for (let index = 0; index < length; index++) {
    difference |= (actual.charCodeAt(index) || 0) ^
      (expected.charCodeAt(index) || 0);
  }
  return difference === 0;
}

function forbidden(): Response {
  return new Response(JSON.stringify({ error: "Dashboard request rejected" }), {
    status: 403,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/json",
    },
  });
}

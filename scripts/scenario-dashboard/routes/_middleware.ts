/** Request security boundary for dashboard pages and APIs. */
import {
  getDashboardSecurity,
  validateDashboardRequest,
} from "../services/dashboard_security.ts";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * Authenticate an intentionally non-loopback dashboard and require the
 * launch capability for every state-changing API request.
 */
export async function handler(
  request: Request,
  context: { next: () => Promise<Response> },
): Promise<Response> {
  const path = new URL(request.url).pathname;
  const isMutation = path.startsWith("/api/") &&
    !SAFE_METHODS.has(request.method);
  const rejection = validateDashboardRequest(
    request,
    getDashboardSecurity(),
    isMutation,
  );
  return rejection ?? await context.next();
}

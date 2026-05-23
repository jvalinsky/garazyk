/** Shared boilerplate utilities for scenario authoring. @module boilerplate */
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import type { ScenarioResult } from "./runner.ts";

/** Current timestamp as an ISO-8601 string suitable for ATProto record createdAt fields. */
export function now(): string {
  return new Date().toISOString();
}

/**
 * Call an endpoint and record pass/skip/fail on a ScenarioResult.
 *
 * XRPC endpoints that return HTTP 404 or 501 are treated as unavailable and
 * recorded as skipped.  All other errors are recorded as failures.
 *
 * @typeParam T - The type returned by the endpoint function.
 * @returns The response value on success, or null if the call was skipped or failed.
 */
export async function tryEndpoint<T>(
  result: ScenarioResult,
  label: string,
  fn: () => Promise<T>,
  summary?: (t: T) => string,
): Promise<T | null> {
  try {
    const val = await fn();
    result.stepPassed(label, summary ? summary(val) : undefined);
    return val;
  } catch (e: unknown) {
    if (e instanceof XrpcError && (e.status === 404 || e.status === 501)) {
      result.stepSkipped(label, `endpoint not available (HTTP ${e.status})`);
    } else if (e instanceof XrpcError && e.status === 403) {
      result.stepSkipped(label, `access denied (HTTP 403) — requires elevated role`);
    } else if (e instanceof XrpcError && e.status === 400) {
      const body = typeof e.body === "string" ? e.body : JSON.stringify(e.body ?? "");
      if (body.includes("not implemented") || body.includes("unknown method")) {
        result.stepSkipped(label, `endpoint not implemented`);
      } else {
        result.stepFailed(label, `HTTP 400: ${body.substring(0, 200)}`);
      }
    } else {
      result.stepFailed(label, String(e instanceof Error ? e.message : e));
    }
    return null;
  }
}

/**
 * Create a new account on the PDS, or log in if the account already exists.
 *
 * On success the returned session object has `did`, `accessJwt`, and `refreshJwt`
 * properties.  The caller is responsible for assigning these to the `Actor`:
 *
 * ```ts
 * const session = await createAccountOrLogin(client, actor);
 * if (session) {
 *   actor.did = session.did;
 *   actor.accessJwt = session.accessJwt;
 * }
 * ```
 */
export async function createAccountOrLogin(
  client: XrpcClient,
  params: { handle: string; email: string; password: string },
): Promise<{ did: string; accessJwt: string; refreshJwt: string; handle: string }> {
  try {
    const res = await client.agent.createAccount({
      handle: params.handle,
      email: params.email,
      password: params.password,
    });
    return res.data;
  } catch (e: unknown) {
    if (
      e instanceof Error &&
      (e.message.includes("already exists") || e.message.includes("HandleAlreadyExists"))
    ) {
      const res = await client.agent.login({
        identifier: params.handle,
        password: params.password,
      });
      return res.data;
    }
    throw e;
  }
}

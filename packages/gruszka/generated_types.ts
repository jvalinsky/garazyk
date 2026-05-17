/**
 * Root-safe public types for generated AT Protocol method proxies.
 *
 * Exact generated Lexicon definitions remain available from
 * `@garazyk/gruszka/lexicons`; these aliases keep the root API compact enough
 * for Deno/JSR documentation.
 *
 * @module generated_types
 */

/**
 * Dynamic response body returned by the ergonomic root XRPC proxy.
 *
 * @remarks
 * Lexicon and XRPC allow endpoints with optional output schemas and dynamic
 * JSON bodies. The root `client.api` proxy intentionally uses this escape hatch
 * for script ergonomics; import exact generated types from
 * `@garazyk/gruszka/lexicons` when strict response shapes are required.
 *
 * @alpha
 */
// deno-lint-ignore no-explicit-any -- Deliberate root XRPC escape hatch for dynamic Lexicon output.
export type DynamicXrpcResponse = any;

/** Namespace-shaped generated client proxy for XRPC methods. */
export interface GeneratedClient {
  /** Nested namespace or callable XRPC method. */
  [namespace: string]: GeneratedClient;
  /**
   * Invoke the selected XRPC method.
   * @param params - Query parameters or procedure input.
   * @param token - Optional bearer token.
   * @returns The parsed response body.
   */
  <T = DynamicXrpcResponse>(
    params?: Record<string, unknown>,
    token?: string,
  ): Promise<T>;
}

/** All generated Lexicon method identifiers. */
export type LexiconIds = string;

/** Generated method identifiers whose type is `query`. */
export type LexiconQueryIds = string;

/** Generated method identifiers whose type is `procedure`. */
export type LexiconProcedureIds = string;

/** Query parameter object for a generated query method. */
export type QueryParams<_K extends LexiconQueryIds> = Record<string, unknown>;

/** Query response body for a generated query method. */
export type QueryOutput<_K extends LexiconQueryIds> = DynamicXrpcResponse;

/** Procedure input body for a generated procedure method. */
export type ProcedureInput<_K extends LexiconProcedureIds> = unknown;

/** Procedure response body for a generated procedure method. */
export type ProcedureOutput<_K extends LexiconProcedureIds> =
  DynamicXrpcResponse;

/**
 * Root-safe public types for generated AT Protocol method proxies.
 *
 * Exact generated Lexicon definitions remain available from
 * `@garazyk/gruszka/lexicons`; these aliases keep the root API compact enough
 * for Deno/JSR documentation.
 *
 * @module generated_types
 */

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
  (
    params?: Record<string, unknown>,
    token?: string,
  ): Promise<unknown>;
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
export type QueryOutput<_K extends LexiconQueryIds> = unknown;

/** Procedure input body for a generated procedure method. */
export type ProcedureInput<_K extends LexiconProcedureIds> = unknown;

/** Procedure response body for a generated procedure method. */
export type ProcedureOutput<_K extends LexiconProcedureIds> = unknown;

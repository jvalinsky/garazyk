/**
 * Strongly typed XRPC client for AT Protocol services.
 *
 * Root exports focus on the generated namespace client, typed query/procedure
 * helpers, raw transport, errors, and firehose primitives. Generated Lexicon
 * definitions live under `@garazyk/gruszka/lexicons`; hand-written namespace
 * clients live under `@garazyk/gruszka/legacy-clients`.
 *
 * @module gruszka
 */

export { XrpcClient, XrpcError } from "./client.ts";
export type { AgentProxy, TransportResponse } from "./client.ts";
export { TransportError, TransportLayer } from "./transport.ts";
export type { RequestOptions } from "./transport.ts";
export {
  FirehoseClient,
  FirehoseEvent,
  FirehoseFrameParseError,
  firehoseEventFromFrame,
  parseFirehoseFrame,
} from "./firehose.ts";
export { RawClient } from "./clients/raw.ts";
export type {
  DynamicXrpcResponse,
  GeneratedClient,
  LexiconIds,
  LexiconProcedureIds,
  LexiconQueryIds,
  ProcedureInput,
  ProcedureOutput,
  QueryOutput,
  QueryParams,
} from "./generated_types.ts";

export {
  generateInviteCode,
  generatePassword,
  randomString,
} from "./account_ops.ts";
export { formatBytes } from "./format.ts";

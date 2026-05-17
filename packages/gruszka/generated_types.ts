/**
 * Public re-exports for exact generated AT Protocol Lexicon types.
 *
 * @module generated_types
 */

export {
  LEXICON_METHOD_INPUT_ENCODINGS,
  LEXICON_METHOD_OUTPUT_ENCODINGS,
  LEXICON_METHOD_TYPES,
} from "./lexicons.ts";

export type {
  BinaryXrpcResponse,
  GeneratedClient,
  LexiconDefs,
  LexiconIds,
  LexiconProcedureIds,
  LexiconQueryIds,
  Lexicons,
  ProcedureInput,
  ProcedureInputEncoding,
  ProcedureOutput,
  ProcedureOutputEncoding,
  QueryOutput,
  QueryOutputEncoding,
  QueryParams,
} from "./lexicons.ts";

// deno-lint-ignore no-explicit-any -- Backward-compatible alias for older callers.
export type DynamicXrpcResponse = any;

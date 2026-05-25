/**
 * Unified entrypoint for TUI E2E automation testing tools.
 *
 * Import from `@garazyk/tui/testing` in Deno test files.
 *
 * @module tui/testing
 */

export {
  type CastRecorderSink,
  type HarnessOptions,
  VirtualTuiHarness,
} from "./harness.ts";

export { getByRole, getByText, Locator } from "./locators.ts";

export {
  extractTextFromBounds,
  renderTdomToXml,
  serializeTdom,
  type TdomElement,
} from "./tdom.ts";

export {
  type AsciicastFrame,
  attachRecorder,
  CastRecorder,
  type CastRecorderOptions,
  TuiSessionRecorder,
} from "./recorder.ts";

export {
  type AsciicastFile,
  type AsciicastHeader,
  type CastEvent,
  type CastEventCode,
  encodeKeyInput,
  extractMarkers,
  parseAsciicast,
  serializeAsciicast,
} from "./cast.ts";

export {
  parseReplayScript,
  type ReplayStep,
  serializeReplayScript,
} from "./replay_types.ts";

export { replayScript, type ReplayScriptOptions } from "./replay.ts";

export {
  actionsFor,
  buildSpatialRelations,
  buildTuiWorldFromElements,
  explain,
  findNodes,
  getByRef as getWorldByRef,
  getByRole as getWorldByRole,
  nearest,
  primaryAction,
  rectContains,
  rectOverlaps,
  related,
  toWorldRect,
  type TuiAction,
  type TuiDiagnostic,
  type TuiEdge,
  type TuiEvidence,
  type TuiNode,
  type TuiRect,
  type TuiWorld,
  validate,
  type WorldElementInput,
  type WorldQuery,
  worldQuery,
} from "./world.ts";

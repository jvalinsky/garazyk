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
  createDashboardHarness,
  type DashboardState,
  startMcpServer,
} from "./mcp_server.ts";

export {
  type AsciicastFrame,
  attachRecorder,
  CastRecorder,
  type CastRecorderOptions,
  TuiSessionRecorder,
} from "./recorder.ts";

export {
  type AsciicastHeader,
  type CastEvent,
  type CastEventCode,
  encodeKeyInput,
  extractMarkers,
  parseAsciicast,
  serializeAsciicast,
  type AsciicastFile,
} from "./cast.ts";

export {
  parseReplayScript,
  type ReplayStep,
  serializeReplayScript,
} from "./replay_types.ts";

export { type ReplayScriptOptions, replayScript } from "./replay.ts";

/**
 * Unified entrypoint for TUI E2E automation testing tools.
 *
 * Import from `@garazyk/tui/testing` in Deno test files.
 *
 * @module tui/testing
 */

export {
  VirtualTuiHarness,
  type HarnessOptions,
} from "./harness.ts";

export {
  Locator,
  getByText,
  getByRole,
} from "./locators.ts";

export {
  serializeTdom,
  renderTdomToXml,
  extractTextFromBounds,
  type TdomElement,
} from "./tdom.ts";

export {
  startMcpServer,
  createDashboardHarness,
  handleMcpMessage,
  type DashboardState,
} from "./mcp_server.ts";

export {
  TuiSessionRecorder,
  type AsciicastFrame,
} from "./recorder.ts";


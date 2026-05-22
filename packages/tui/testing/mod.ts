/**
 * Unified entrypoint for TUI E2E automation testing tools.
 *
 * Import from `@garazyk/tui/testing` in Deno test files.
 *
 * @module tui/testing
 */

export { type HarnessOptions, VirtualTuiHarness } from "./harness.ts";

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
  handleMcpMessage,
  startMcpServer,
} from "./mcp_server.ts";

export { type AsciicastFrame, TuiSessionRecorder } from "./recorder.ts";

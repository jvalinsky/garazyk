/**
 * Model Context Protocol (MCP) Server for Headless TUI Automation
 *
 * Exposes the VirtualTuiHarness, locators, and TDOM serializers over
 * a standard stdin/stdout JSON-RPC 2.0 interface. Bundles a stateful
 * virtual Scenario Dashboard to allow interactive agent navigation.
 *
 * @module tui/testing/mcp_server
 */

import { DEFAULT_STYLE, ScreenBuffer } from "../renderer.ts";
import { VirtualTuiHarness } from "./harness.ts";
import { CastRecorder } from "./recorder.ts";
import { renderTdomToXml, serializeTdom, type TdomElement } from "./tdom.ts";
import { getByRole, getByText } from "./locators.ts";
import type { ResolvedNode } from "../layout_tree.ts";

/** Internal state structure for the mounted Scenario Dashboard component. */
export interface DashboardState {
  scenarios: string[];
  selectedIdx: number;
  filterTerm: string;
  isRunning: boolean;
  statusMessage: string;
  runCount: number;
}

/** Initial default state for the dashboard. */
export const DEFAULT_DASHBOARD_STATE: DashboardState = {
  scenarios: [
    "01_account_lifecycle",
    "53_phone_verification",
    "82_chat_persistence",
  ],
  selectedIdx: 0,
  filterTerm: "",
  isRunning: false,
  statusMessage: "System Ready",
  runCount: 0,
};

/** High-level layout definition for the Scenario Dashboard. */
export const DASHBOARD_LAYOUT: ResolvedNode = {
  id: "root-dashboard",
  x: 0,
  y: 0,
  width: 80,
  height: 24,
  children: [
    {
      id: "header-panel",
      x: 0,
      y: 0,
      width: 80,
      height: 3,
      children: [],
    },
    {
      id: "search-panel",
      x: 0,
      y: 3,
      width: 80,
      height: 3,
      children: [],
    },
    {
      id: "scenarios-list",
      x: 0,
      y: 6,
      width: 40,
      height: 15,
      children: [],
    },
    {
      id: "details-card",
      x: 40,
      y: 6,
      width: 40,
      height: 15,
      children: [],
    },
    {
      id: "status-bar",
      x: 0,
      y: 21,
      width: 80,
      height: 3,
      children: [],
    },
  ],
};

/** Render function for the Scenario Dashboard component. */
export function renderDashboard(
  buf: ScreenBuffer,
  state: DashboardState,
): void {
  // Clear and fill base background
  buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);

  // 1. Header (y: 0-2)
  buf.fillRect(0, 0, 80, 3, " ", {
    ...DEFAULT_STYLE,
    fg: 7,
    bg: 4,
    bold: true,
  });
  buf.write(2, 1, "GARAZYK SCENARIO RUNNER DASHBOARD", {
    ...DEFAULT_STYLE,
    fg: 7,
    bg: 4,
    bold: true,
  });
  buf.write(60, 1, `Runs Executed: ${state.runCount}`, {
    ...DEFAULT_STYLE,
    fg: 7,
    bg: 4,
  });

  // 2. Search Panel (y: 3-5)
  buf.fillRect(0, 3, 80, 3, " ", { ...DEFAULT_STYLE, fg: 7, bg: 0 });
  buf.write(
    2,
    4,
    `Search: [${state.filterTerm || "Type to filter..."}]`,
    DEFAULT_STYLE,
  );

  // 3. Scenarios List (y: 6-20, x: 0-39)
  buf.fillRect(0, 6, 40, 15, " ", { ...DEFAULT_STYLE, fg: 7, bg: 0 });
  buf.write(2, 7, "AVAILABLE SCENARIOS:", {
    ...DEFAULT_STYLE,
    bold: true,
    underline: true,
  });

  const filtered = state.scenarios.filter((s) =>
    s.toLowerCase().includes(state.filterTerm.toLowerCase())
  );

  for (let i = 0; i < filtered.length; i++) {
    const isSelected = i === state.selectedIdx;
    const style = isSelected
      ? { ...DEFAULT_STYLE, fg: 2, bg: 0, bold: true }
      : DEFAULT_STYLE;
    const prefix = isSelected ? "> " : "  ";
    buf.write(2, 9 + i, `${prefix}${filtered[i]}`, style);
  }

  // 4. Details Card (y: 6-20, x: 40-79)
  buf.fillRect(40, 6, 40, 15, " ", { ...DEFAULT_STYLE, fg: 7, bg: 0 });
  const activeScenario = filtered[state.selectedIdx] || "None Selected";
  buf.write(42, 7, "SCENARIO DETAILS:", {
    ...DEFAULT_STYLE,
    bold: true,
    underline: true,
  });
  buf.write(42, 9, `Name: ${activeScenario}`, DEFAULT_STYLE);
  buf.write(
    42,
    11,
    `Status: ${state.isRunning ? "RUNNING" : "STOPPED"}`,
    DEFAULT_STYLE,
  );

  const btnStyle = state.isRunning
    ? { ...DEFAULT_STYLE, fg: 7, bg: 1, bold: true }
    : { ...DEFAULT_STYLE, fg: 7, bg: 2, bold: true };
  const btnLabel = state.isRunning ? "[ STOP RUN ]" : "[ START RUN ]";
  buf.write(42, 13, btnLabel, btnStyle);

  // 5. Status Bar (y: 21-23)
  buf.fillRect(0, 21, 80, 3, " ", { ...DEFAULT_STYLE, fg: 7, bg: 8 });
  buf.write(2, 22, `Status: ${state.statusMessage}`, {
    ...DEFAULT_STYLE,
    fg: 7,
    bg: 8,
    bold: true,
  });
}

/** Configures and returns a live VirtualTuiHarness for the Scenario Dashboard. */
export function createDashboardHarness(
  initialState = DEFAULT_DASHBOARD_STATE,
): {
  harness: VirtualTuiHarness;
  state: DashboardState;
  recorder?: CastRecorder;
} {
  const state = { ...initialState };
  const harness = new VirtualTuiHarness(
    80,
    24,
    (buf) => renderDashboard(buf, state),
  );

  let recorder: CastRecorder | undefined;
  const recordPath = Deno.env.get("GARAZYK_RECORD_CAST");
  if (recordPath) {
    const path = recordPath === "1"
      ? `dashboard-mcp-${Date.now()}.cast`
      : recordPath;
    recorder = new CastRecorder(harness, {
      path,
      title: "Garazyk MCP Dashboard",
    });
    harness.attachRecorder(recorder);
  }

  harness.onKey((key) => {
    recorder?.recordKey(key);
    // Process list navigation
    if (key.key === "down" || key.key === "j") {
      state.selectedIdx = Math.min(
        state.selectedIdx + 1,
        state.scenarios.length - 1,
      );
      state.statusMessage = `Highlighted ${state.scenarios[state.selectedIdx]}`;
    } else if (key.key === "up" || key.key === "k") {
      state.selectedIdx = Math.max(state.selectedIdx - 1, 0);
      state.statusMessage = `Highlighted ${state.scenarios[state.selectedIdx]}`;
    } else if (key.key === "enter") {
      // Toggle running state
      state.isRunning = !state.isRunning;
      if (state.isRunning) {
        state.runCount += 1;
        state.statusMessage = `Started run of ${
          state.scenarios[state.selectedIdx]
        }!`;
      } else {
        state.statusMessage = `Stopped run of ${
          state.scenarios[state.selectedIdx]
        }.`;
      }
    } else if (key.key.length === 1) {
      // Direct typing simulates filtering
      state.filterTerm += key.key;
      state.selectedIdx = 0;
      state.statusMessage = `Filtering scenarios: "${state.filterTerm}"`;
    } else if (key.key === "backspace") {
      state.filterTerm = state.filterTerm.slice(0, -1);
      state.selectedIdx = 0;
      state.statusMessage = `Filtering scenarios: "${state.filterTerm}"`;
    } else if (key.key === "escape") {
      state.filterTerm = "";
      state.statusMessage = "Cleared filters.";
    }
  });

  return { harness, state, recorder };
}

// ---------------------------------------------------------------------------
// MCP Server via Official SDK
// ---------------------------------------------------------------------------

import { Server } from "npm:@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "npm:@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "npm:@modelcontextprotocol/sdk/types.js";

function findNode(el: TdomElement, targetId: string): TdomElement | undefined {
  if (el.id === targetId) return el;
  for (const c of el.children) {
    const found = findNode(c, targetId);
    if (found) return found;
  }
  return undefined;
}

export async function startMcpServer(): Promise<void> {
  const { harness } = createDashboardHarness();
  const layout = DASHBOARD_LAYOUT;

  const server = new Server(
    { name: "garazyk-tui-mcp", version: "1.0.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
      tools: [
        {
          name: "tui_inspect",
          description: "Returns the current visual flat text screen buffer and hierarchical TDOM XML layout tree representation.",
          inputSchema: { type: "object", properties: {} },
        },
        {
          name: "tui_action",
          description: "Simulates interactive keystrokes or mouse click coordinate events to drive state changes.",
          inputSchema: {
            type: "object",
            properties: {
              action: {
                type: "string",
                enum: ["press_key", "type", "click"],
                description: "Simulation type: press_key for control keys, type for characters, click for click coordinate zones.",
              },
              value: {
                type: "string",
                description: "Key name (e.g. 'down', 'enter', 'backspace'), text content to type, or component layout ID to click.",
              },
            },
            required: ["action", "value"],
          },
        },
        {
          name: "tui_assert",
          description: "Semantic assertions over specific components or visible screen coordinates.",
          inputSchema: {
            type: "object",
            properties: {
              selector: { type: "string", description: "TDOM component ID (e.g. 'status-bar') or 'screen' for the full buffer." },
              condition: { type: "string", enum: ["contains_text", "visible"], description: "The verification assert rule." },
              expected: { type: "string", description: "Value or substring expected to be matched." },
            },
            required: ["selector", "condition", "expected"],
          },
        },
      ],
    };
  });

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args = {} } = request.params;
    
    try {
      switch (name) {
        case "tui_inspect": {
          const tdom = serializeTdom(harness.buffer, layout);
          const xml = renderTdomToXml(tdom);
          const flatScreen = harness.dumpScreen();

          const payloadText = `=== TDOM XML LAYOUT ===\n${xml}\n\n=== SCREEN BUFFER DUMP ===\n${flatScreen}`;
          return { content: [{ type: "text", text: payloadText }] };
        }

        case "tui_action": {
          const act = args.action as string;
          const val = args.value as string;

          if (act === "press_key") {
            harness.emitKey(val);
          } else if (act === "type") {
            for (const c of val) {
              harness.emitKey(c);
            }
          } else if (act === "click") {
            const tdom = serializeTdom(harness.buffer, layout);
            const node = findNode(tdom, val);
            if (!node) {
              throw new Error(`Failed to find clickable component with ID: ${val}`);
            }
            harness.emitKey("enter");
          } else {
            throw new Error(`Unsupported action parameter: ${act}`);
          }

          const updatedTdom = serializeTdom(harness.buffer, layout);
          const updatedXml = renderTdomToXml(updatedTdom);
          const updatedScreen = harness.dumpScreen();

          return {
            content: [
              {
                type: "text",
                text: `Action executed successfully.\n\n=== NEW TDOM LAYOUT ===\n${updatedXml}\n\n=== NEW SCREEN BUFFER ===\n${updatedScreen}`,
              },
            ],
          };
        }

        case "tui_assert": {
          const selector = args.selector as string;
          const cond = args.condition as string;
          const expected = args.expected as string;

          if (selector === "screen") {
            const text = harness.dumpScreen();
            const passed = text.includes(expected);
            if (!passed) {
              throw new Error(`Screen assertion failed. Expected text "${expected}" to be visible, but got screen:\n${text}`);
            }
          } else {
            const tdom = serializeTdom(harness.buffer, layout);
            const node = findNode(tdom, selector);
            if (!node) {
              throw new Error(`Assertion failed. Target selector element ID not found: ${selector}`);
            }

            if (cond === "visible") {
              const passed = node.width > 0 && node.height > 0;
              if (!passed) {
                throw new Error(`Element "${selector}" is not visible (dimensions ${node.width}x${node.height}).`);
              }
            } else if (cond === "contains_text") {
              const passed = node.text.includes(expected);
              if (!passed) {
                throw new Error(`Element "${selector}" contains text "${node.text}", which does not match expected "${expected}".`);
              }
            }
          }

          return { content: [{ type: "text", text: `Assertion passed successfully.` }] };
        }

        default:
          throw new Error(`Method not found: ${name}`);
      }
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error: ${(err as Error).message}` }],
        isError: true,
      };
    }
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

// Standalone execution path
if (import.meta.main) {
  startMcpServer().catch(console.error);
}

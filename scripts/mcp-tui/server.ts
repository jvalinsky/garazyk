import { createSession, sessionSnapshot, sessionPressKey, sessionType, sessionStartRecording, sessionStopRecording } from "./session.ts";
import { extractTree } from "../scenario-dashboard/tui_scanner.ts";
import type { TuiElement } from "../scenario-dashboard/tui_types.ts";
import { Server } from "npm:@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "npm:@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "npm:@modelcontextprotocol/sdk/types.js";

const BASE_DIR = Deno.cwd();

function findElementFuzzy(node: TuiElement, ref: string): TuiElement | null {
  if (node.id === ref || node.id.includes(ref)) return node;
  for (const child of node.children) {
    const found = findElementFuzzy(child, ref);
    if (found) return found;
  }
  return null;
}

const server = new Server(
  { name: "garazyk-tui-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "tui_snapshot",
        description: "Returns the current TUI state as a structured YAML tree with semantic roles (panel, service, scenario, run, heading, state, list, table) and stable element references for interaction. Includes overlay panels if active. Each panel shows its focused state, cursor position, and all interactable items.",
        inputSchema: {
          type: "object",
          properties: {
            boxes: { type: "boolean", description: "Include bounding box coordinates [box=x,y,w,h] for each element" },
            panel: { type: "string", enum: ["network", "scenarios", "run", "history"], description: "Scope to a single panel" },
          },
        },
      },
      {
        name: "tui_action",
        description: "Send a keystroke or type text into the TUI. Returns the updated structured YAML snapshot so you can observe the effect. Can interact with overlay panels when they are active. Use press_key for control keys (down, up, tab, enter, escape, backspace, ?, 1-4, c) and type for character sequences (e.g. typing a search filter).",
        inputSchema: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["press_key", "type"], description: "press_key for control keys, type for character strings" },
            value: { type: "string", description: "Key name (e.g. 'down', 'up', 'tab', 'enter', 'escape', 'backspace', '?', '1', 'c') or text to type character by character" },
          },
          required: ["action", "value"],
        },
      },
      {
        name: "tui_rec_start",
        description: "Start recording the current TUI session to an asciicast. All subsequent frames and key inputs are captured until tui_rec_stop is called.",
        inputSchema: {
          type: "object",
          properties: {
            title: { type: "string", description: "Optional recording title for the HTML page" },
            outputDir: { type: "string", description: "Output directory (default: scripts/scenarios/reports/tui-capture/mcp-<timestamp>)" },
          },
        },
      },
      {
        name: "tui_rec_stop",
        description: "Stop recording and export the session as a standalone HTML page with Asciinema Player. Returns paths to the cast file (.cast) and HTML file.",
        inputSchema: {
          type: "object",
          properties: {},
        },
      },
      {
        name: "tui_inspect",
        description: "Inspect the full metadata properties of a specific element reference (fuzzy matches allowed).",
        inputSchema: {
          type: "object",
          properties: {
            ref: { type: "string", description: "The reference ID or partial ID to inspect" }
          },
          required: ["ref"]
        }
      },
      {
        name: "tui_reset",
        description: "Resets the TUI session back to the initial state.",
        inputSchema: {
          type: "object",
          properties: {}
        }
      },
    ],
  };
});

let session = createSession();

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  try {
    switch (name) {
      case "tui_snapshot": {
        const yaml = sessionSnapshot(session, {
          boxes: !!args.boxes,
          panel: args.panel as string | undefined,
        });
        return { content: [{ type: "text", text: yaml }] };
      }

      case "tui_action": {
        const action = args.action as string;
        const value = args.value as string;
        if (action === "press_key") {
          const yaml = await sessionPressKey(session, value);
          return { content: [{ type: "text", text: yaml }] };
        }
        if (action === "type") {
          const yaml = await sessionType(session, value);
          return { content: [{ type: "text", text: yaml }] };
        }
        throw new Error(`Unknown action: ${action}`);
      }

      case "tui_rec_start": {
        await sessionStartRecording(session, args.title as string | undefined, args.outputDir as string | undefined, BASE_DIR);
        return { content: [{ type: "text", text: "Recording started." }] };
      }

      case "tui_rec_stop": {
        const { castPath, htmlPath } = await sessionStopRecording(session);
        return {
          content: [{
            type: "text",
            text: `Recording complete.\nCast: ${castPath}\nHTML: ${htmlPath}`,
          }],
        };
      }

      case "tui_inspect": {
        const ref = args.ref as string;
        const root = extractTree(session.harness.buffer, session.lastMeta);
        const found = findElementFuzzy(root, ref);
        if (!found) {
          throw new Error(`Reference not found: ${ref}`);
        }
        // Omit children for cleaner output
        const { children, ...rest } = found;
        return {
          content: [{ type: "text", text: JSON.stringify(rest, null, 2) }],
        };
      }

      case "tui_reset": {
        session = createSession();
        return { content: [{ type: "text", text: "Session reset initiated" }] };
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

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

if (import.meta.main) {
  main().catch(console.error);
}

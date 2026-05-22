/**
 * Unit Tests for the TUI MCP Server and Interactive Dashboard
 *
 * Verifies standard JSON-RPC protocol handling, schema compliance,
 * inspector lookups, state action dispatches, and semantic assertions.
 *
 * @module tui/testing/mcp_server_test
 */

import { assert, assertEquals } from "@std/assert";
import {
  createDashboardHarness,
  DASHBOARD_LAYOUT,
  handleMcpMessage,
} from "./mcp_server.ts";

// ---------------------------------------------------------------------------
// 1. JSON-RPC Protocol Handling Tests
// ---------------------------------------------------------------------------

Deno.test("MCP Server: handles invalid JSON-RPC payload errors gracefully", () => {
  const { harness } = createDashboardHarness();

  // Test completely broken JSON
  const brokenJson = "{broken json";
  const res1 = JSON.parse(
    handleMcpMessage(brokenJson, harness, DASHBOARD_LAYOUT),
  );
  assert(res1.error);
  assertEquals(res1.error.code, -32700);

  // Test missing version
  const badVersion = JSON.stringify({ id: 1, method: "tools/list" });
  const res2 = JSON.parse(
    handleMcpMessage(badVersion, harness, DASHBOARD_LAYOUT),
  );
  assert(res2.error);
  assertEquals(res2.error.code, -32600);
});

Deno.test("MCP Server: supports initialize handshakes", () => {
  const { harness } = createDashboardHarness();

  const initMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 100,
    method: "initialize",
    params: {},
  });

  const res = JSON.parse(handleMcpMessage(initMsg, harness, DASHBOARD_LAYOUT));
  assertEquals(res.id, 100);
  assertEquals(res.result.serverInfo.name, "garazyk-tui-mcp");
  assertEquals(res.result.protocolVersion, "2024-11-05");
});

Deno.test("MCP Server: listTools returns schemas for inspect, action, and assert", () => {
  const { harness } = createDashboardHarness();

  const listMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 101,
    method: "tools/list",
  });

  const res = JSON.parse(handleMcpMessage(listMsg, harness, DASHBOARD_LAYOUT));
  assertEquals(res.id, 101);
  const tools = res.result.tools;
  assertEquals(tools.length, 3);

  const names = tools.map((t: any) => t.name);
  assert(names.includes("tui_inspect"));
  assert(names.includes("tui_action"));
  assert(names.includes("tui_assert"));
});

// ---------------------------------------------------------------------------
// 2. Interactive Stateful Component Tooling Tests
// ---------------------------------------------------------------------------

Deno.test("MCP Server: tui_inspect retrieves layout XML and text screens", () => {
  const { harness } = createDashboardHarness();

  const inspectMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 102,
    method: "tools/call",
    params: {
      name: "tui_inspect",
    },
  });

  const res = JSON.parse(
    handleMcpMessage(inspectMsg, harness, DASHBOARD_LAYOUT),
  );
  assertEquals(res.id, 102);
  assert(!res.error);

  const textVal = res.result.content[0].text;
  // Assert both flat text and XML structure are outputted
  assert(textVal.includes("=== TDOM XML LAYOUT ==="));
  assert(textVal.includes("=== SCREEN BUFFER DUMP ==="));
  assert(textVal.includes("<root-dashboard"));
  assert(textVal.includes("GARAZYK SCENARIO RUNNER DASHBOARD"));
  assert(textVal.includes("01_account_lifecycle"));
});

Deno.test("MCP Server: tui_action drives component state updates interactively", () => {
  const { harness, state } = createDashboardHarness();

  // 1. Initial assertion - selected item should be index 0
  assertEquals(state.selectedIdx, 0);
  assertEquals(state.isRunning, false);

  // 2. Action: Press down key to move selection to index 1
  const downMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 103,
    method: "tools/call",
    params: {
      name: "tui_action",
      arguments: {
        action: "press_key",
        value: "down",
      },
    },
  });

  const res1 = JSON.parse(handleMcpMessage(downMsg, harness, DASHBOARD_LAYOUT));
  assert(!res1.result.isError);
  assertEquals(state.selectedIdx, 1);
  assertEquals(state.statusMessage, "Highlighted 53_phone_verification");

  // 3. Action: Press enter key to toggle running state
  const enterMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 104,
    method: "tools/call",
    params: {
      name: "tui_action",
      arguments: {
        action: "press_key",
        value: "enter",
      },
    },
  });

  const res2 = JSON.parse(
    handleMcpMessage(enterMsg, harness, DASHBOARD_LAYOUT),
  );
  assert(!res2.result.isError);
  assertEquals(state.isRunning, true);
  assertEquals(state.runCount, 1);
  assertEquals(state.statusMessage, "Started run of 53_phone_verification!");

  const updatedText = res2.result.content[0].text;
  assert(updatedText.includes("Status: Started run of 53_phone_verification!"));
  assert(updatedText.includes("Runs Executed: 1"));
});

Deno.test("MCP Server: tui_assert executes validations correctly", () => {
  const { harness } = createDashboardHarness();

  // 1. Full visual screen assertion
  const screenAssertMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 105,
    method: "tools/call",
    params: {
      name: "tui_assert",
      arguments: {
        selector: "screen",
        condition: "contains_text",
        expected: "GARAZYK SCENARIO RUNNER DASHBOARD",
      },
    },
  });

  const res1 = JSON.parse(
    handleMcpMessage(screenAssertMsg, harness, DASHBOARD_LAYOUT),
  );
  assert(!res1.result.isError);
  assertEquals(res1.result.content[0].text, "Assertion passed successfully.");

  // 2. Component-specific semantic TDOM assertion
  const componentAssertMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 106,
    method: "tools/call",
    params: {
      name: "tui_assert",
      arguments: {
        selector: "header-panel",
        condition: "contains_text",
        expected: "GARAZYK SCENARIO RUNNER DASHBOARD",
      },
    },
  });

  const res2 = JSON.parse(
    handleMcpMessage(componentAssertMsg, harness, DASHBOARD_LAYOUT),
  );
  assert(!res2.result.isError);
  assertEquals(res2.result.content[0].text, "Assertion passed successfully.");

  // 3. Negative assertion (element not found or text mismatch) should report error in content
  const failingAssertMsg = JSON.stringify({
    jsonrpc: "2.0",
    id: 107,
    method: "tools/call",
    params: {
      name: "tui_assert",
      arguments: {
        selector: "header-panel",
        condition: "contains_text",
        expected: "Non-existent Text Content",
      },
    },
  });

  const res3 = JSON.parse(
    handleMcpMessage(failingAssertMsg, harness, DASHBOARD_LAYOUT),
  );
  assert(res3.result.isError);
  assert(res3.result.content[0].text.includes("does not match expected"));
});

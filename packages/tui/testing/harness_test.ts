/**
 * E2E Automation Testing Harness Unit Tests
 *
 * Tests the virtual harness, locator query engines, and TDOM serializers
 * to confirm functional correctness and absolute cross-platform parity.
 *
 * @module tui/testing/harness_test
 */

import { assertEquals, assert } from "@std/assert";
import { VirtualTuiHarness } from "./harness.ts";
import { getByText, getByRole } from "./locators.ts";
import { serializeTdom, renderTdomToXml } from "./tdom.ts";
import { ScreenBuffer, DEFAULT_STYLE } from "../renderer.ts";
import type { ResolvedNode } from "../layout_tree.ts";
import { Keys } from "../input.ts";

// ---------------------------------------------------------------------------
// 1. Basic Harness Render and Dumps Test
// ---------------------------------------------------------------------------

Deno.test("VirtualTuiHarness: mounts, clears, renders and dumps correctly", () => {
  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(1, 1, "Status: Running", { ...DEFAULT_STYLE, bold: true });
    buf.write(1, 2, "CPU: 45%", DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(30, 6, render);

  // Assert standard clean snapshot output
  const cleanScreen = harness.dumpScreen();
  assert(cleanScreen.includes("Status: Running"));
  assert(cleanScreen.includes("CPU: 45%"));

  // Check expected coordinate assertions
  harness.expectToContain("Status: Running");
  harness.expectStyleAt(1, 1, { bold: true });
  harness.expectStyleAt(1, 2, { bold: false });

  // Assert styled dump highlights styled cells
  const styledScreen = harness.dumpScreenStyled();
  assert(styledScreen.includes("[S][t][a][t][u][s][:][ ][R][u][n][n][i][n][g]"));
});

// ---------------------------------------------------------------------------
// 2. Simulated Key Inputs and Event Dispatches
// ---------------------------------------------------------------------------

Deno.test("VirtualTuiHarness: emits key signals and updates component state", async () => {
  let counter = 0;
  const render = (buf: ScreenBuffer) => {
    buf.write(0, 0, `Counter: ${counter}`, DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(20, 2, render);
  harness.onKey((key) => {
    if (key.key === Keys.UP) {
      counter += 1;
    } else if (key.key === Keys.DOWN) {
      counter -= 1;
    } else if (key.key === "c" && key.ctrl) {
      counter = 100;
    }
  });

  harness.expectToContain("Counter: 0");

  // Press UP key
  await harness.emitKey(Keys.UP);
  harness.expectToContain("Counter: 1");

  // Press DOWN key
  await harness.emitKey(Keys.DOWN);
  harness.expectToContain("Counter: 0");

  // Press Ctrl+C modifier key
  await harness.emitKey("c", { ctrl: true });
  harness.expectToContain("Counter: 100");
});

// ---------------------------------------------------------------------------
// 3. Simulated Resize Events
// ---------------------------------------------------------------------------

Deno.test("VirtualTuiHarness: supports onResize signal dispatching and refitting", () => {
  let activeWidth = 20;
  let activeHeight = 5;

  const render = (buf: ScreenBuffer) => {
    buf.write(0, 0, `Size: ${buf.width}x${buf.height}`, DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(activeWidth, activeHeight, render);
  harness.addResizeListener(() => {
    activeWidth = harness.buffer.width;
    activeHeight = harness.buffer.height;
  });

  harness.expectToContain("Size: 20x5");

  // Simulate terminal window resize (SIGWINCH equivalent)
  harness.emitResize(45, 12);
  harness.expectToContain("Size: 45x12");
  assertEquals(activeWidth, 45);
  assertEquals(activeHeight, 12);
});

// ---------------------------------------------------------------------------
// 4. Locators, getByText, getByRole, and Assertions
// ---------------------------------------------------------------------------

Deno.test("Locators & TDOM: getByText scanning and getByRole structural lookup", async () => {
  // Define a static layout mock tree resembling scenario selection
  const mockLayout: ResolvedNode = {
    id: "root-container",
    x: 0,
    y: 0,
    width: 40,
    height: 10,
    children: [
      {
        id: "header-panel",
        x: 0,
        y: 0,
        width: 40,
        height: 2,
        children: [],
      },
      {
        id: "scenario-listbox",
        x: 0,
        y: 2,
        width: 40,
        height: 8,
        children: [],
      },
    ],
  };

  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    // Render header contents
    buf.write(2, 0, "Scenario Runner Dashboard", DEFAULT_STYLE);
    // Render list contents
    buf.write(2, 3, "> 53_phone_verification", { fg: 2, bg: 0, bold: true, dim: false, reverse: false, underline: false });
    buf.write(2, 4, "  01_account_lifecycle", DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(40, 10, render);

  // 1. Test getByText Locator
  const headerLocator = getByText(harness, "Scenario Runner Dashboard");
  headerLocator.toHaveText("Scenario Runner Dashboard");
  
  const textBounds = headerLocator.resolve();
  assertEquals(textBounds.x, 2);
  assertEquals(textBounds.y, 0);

  // Test Regex matching
  const listMatch = getByText(harness, /53_phone_verification/);
  listMatch.toHaveText(/53_phone_/);
  
  // 2. Test getByRole Locator (TDOM traversal)
  const listboxLocator = getByRole(harness, mockLayout, "listbox", { name: "scenario-listbox" });
  listboxLocator.toHaveText("53_phone_verification");
  listboxLocator.toHaveText("01_account_lifecycle");
  listboxLocator.toHaveStyle({ bold: true, fg: 2 }, { x: 2, y: 1 }); // coordinate offset maps to index 3 inside listbox bounds

  // 3. Test TDOM XML Serialization output
  const tdom = serializeTdom(harness.buffer, mockLayout);
  const xml = renderTdomToXml(tdom);
  assert(xml.includes("<root-container"));
  assert(xml.includes("<header-panel"));
  assert(xml.includes("<scenario-listbox"));
  assert(xml.includes("Scenario Runner Dashboard"));
});

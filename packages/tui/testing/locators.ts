/**
 * Playwright-like Locator and Assertion API for Terminal UI
 *
 * Implements high-level locator selectors (getByText, getByRole),
 * input simulators (click, fill, press), and semantic assertions
 * over the VirtualTuiHarness.
 *
 * @module tui/testing/locators
 */

import { assert, assertEquals } from "@std/assert";
import type { VirtualTuiHarness } from "./harness.ts";
import type { CellStyle } from "../renderer.ts";
import type { ResolvedNode } from "../layout_tree.ts";
import { serializeTdom, type TdomElement } from "./tdom.ts";
import type { Key } from "../input.ts";

/** Represents a delayed query locator pointing to one or more TUI components. */
export class Locator {
  private harness: VirtualTuiHarness;
  private resolveQuery: () => { x: number; y: number; width: number; height: number; text?: string } | undefined;
  private description: string;

  constructor(
    harness: VirtualTuiHarness,
    resolveQuery: () => { x: number; y: number; width: number; height: number; text?: string } | undefined,
    description: string,
  ) {
    this.harness = harness;
    this.resolveQuery = resolveQuery;
    this.description = description;
  }

  /** Resolves the locator to its active screen bounding box. Throws if not found. */
  resolve(): { x: number; y: number; width: number; height: number; text?: string } {
    const bounds = this.resolveQuery();
    if (!bounds) {
      throw new Error(`Failed to resolve locator: ${this.description}`);
    }
    return bounds;
  }

  /** Simulate typing a full text string sequentially into the focused component. */
  async fill(text: string): Promise<void> {
    // Verify target exists
    this.resolve();
    for (const char of text) {
      await this.harness.emitKey(char);
    }
  }

  /** Simulate pressing a specific key or escape sequence. */
  async press(keyName: string, modifiers?: Partial<Omit<Key, "key">>): Promise<void> {
    this.resolve();
    await this.harness.emitKey(keyName, modifiers);
  }

  /**
   * Simulate a click action. Focuses the target component by coordinating
   * coordinate clicks or simulating focus events.
   */
  async click(): Promise<void> {
    const bounds = this.resolve();
    const clickX = bounds.x + Math.floor(bounds.width / 2);
    const clickY = bounds.y + Math.floor(bounds.height / 2);
    
    // In TUI context, clicking targets often activates them or focuses them.
    // If the harness has coordinate click handlers, we would dispatch it.
    // For general keys, we simulate an active click confirmation (e.g. ENTER) or tab-to focus.
    await this.harness.emitKey("enter");
  }

  /** Assert that the locator contains the expected text substring or matches a regex. */
  toHaveText(expected: string | RegExp): void {
    const bounds = this.resolve();
    const text = bounds.text !== undefined ? bounds.text : this.harness.dumpScreen();
    
    if (expected instanceof RegExp) {
      assert(
        expected.test(text),
        `Expected locator "${this.description}" text "${text}" to match regex ${expected}`
      );
    } else {
      assert(
        text.includes(expected),
        `Expected locator "${this.description}" text to contain "${expected}", but got:\n${text}`
      );
    }
  }

  /** Assert that specific coordinates inside the locator have the correct style attributes. */
  toHaveStyle(style: Partial<CellStyle>, offset = { x: 0, y: 0 }): void {
    const bounds = this.resolve();
    const absX = bounds.x + offset.x;
    const absY = bounds.y + offset.y;
    this.harness.expectStyleAt(absX, absY, style);
  }
}

// ---------------------------------------------------------------------------
// Selector Factories
// ---------------------------------------------------------------------------

/** Scan the virtual screen cells to locate the bounding box of a specific text. */
export function getByText(harness: VirtualTuiHarness, textOrRegex: string | RegExp): Locator {
  return new Locator(
    harness,
    () => {
      const screenLines = harness.dumpScreen().split("\n");
      for (let y = 0; y < screenLines.length; y++) {
        const line = screenLines[y]!;
        if (textOrRegex instanceof RegExp) {
          const match = line.match(textOrRegex);
          if (match && match.index !== undefined) {
            return { x: match.index, y, width: match[0].length, height: 1, text: match[0] };
          }
        } else {
          const idx = line.indexOf(textOrRegex);
          if (idx !== -1) {
            return { x: idx, y, width: textOrRegex.length, height: 1, text: textOrRegex };
          }
        }
      }
      return undefined;
    },
    `getByText(${textOrRegex})`,
  );
}

/** Recursively searches the TDOM tree to find a node by ID, role, or matching name. */
function findInTdom(element: TdomElement, role: string, name: string | RegExp): TdomElement | undefined {
  const matchesRole = element.id?.toLowerCase().includes(role.toLowerCase()) || false;
  let matchesName = false;

  if (name instanceof RegExp) {
    matchesName = name.test(element.text) || (element.id !== undefined && name.test(element.id));
  } else {
    matchesName = element.text.includes(name) || element.id?.includes(name) || false;
  }

  if (matchesRole && matchesName) {
    return element;
  }

  for (const child of element.children) {
    const found = findInTdom(child, role, name);
    if (found) return found;
  }
  return undefined;
}

/** Locates a component semantically by structural role and text name from the solved layout. */
export function getByRole(
  harness: VirtualTuiHarness,
  layout: ResolvedNode,
  role: string,
  options: { name: string | RegExp },
): Locator {
  return new Locator(
    harness,
    () => {
      const tdom = serializeTdom(harness.buffer, layout);
      const match = findInTdom(tdom, role, options.name);
      if (match) {
        return { x: match.x, y: match.y, width: match.width, height: match.height, text: match.text };
      }
      return undefined;
    },
    `getByRole(${role}, { name: ${options.name} })`,
  );
}

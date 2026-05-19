/**
 * Focus Ring — manages which panel has keyboard focus
 *
 * Panels are ordered: network → scenarios → run → history.
 * Tab/Shift+Tab cycle through them. Numeric keys 1-4 jump directly.
 *
 * @module tui/focus
 */

import { PANEL_IDS, type PanelId } from "./layout.ts";

/** Manages which panel currently has keyboard focus. */
export class FocusRing {
  private index: number = 0;

  /** Get the currently focused panel ID. */
  get current(): PanelId {
    return PANEL_IDS[this.index]!;
  }

  /** Get the current focus index (0-3). */
  get currentIndex(): number {
    return this.index;
  }

  /** Move focus to the next panel (Tab). */
  next(): PanelId {
    this.index = (this.index + 1) % PANEL_IDS.length;
    return this.current;
  }

  /** Move focus to the previous panel (Shift+Tab). */
  prev(): PanelId {
    this.index = (this.index - 1 + PANEL_IDS.length) % PANEL_IDS.length;
    return this.current;
  }

  /** Jump to a specific panel by index (1-4). Returns true if changed. */
  jump(index: number): boolean {
    if (index < 0 || index >= PANEL_IDS.length) return false;
    if (this.index === index) return false;
    this.index = index;
    return true;
  }

  /** Jump to a specific panel by ID. Returns true if changed. */
  jumpTo(id: PanelId): boolean {
    const idx = PANEL_IDS.indexOf(id);
    if (idx === -1 || idx === this.index) return false;
    this.index = idx;
    return true;
  }

  /** Check if a panel ID is currently focused. */
  isFocused(id: PanelId): boolean {
    return this.current === id;
  }

  /** Reset focus to the first panel. */
  reset(): void {
    this.index = 0;
  }
}

/**
 * Terminal runtime I/O for the TUI package.
 *
 * This subpath exports functions that interact with the terminal
 * (stdin, stdout, environment variables). Import from `@garazyk/tui/runtime`
 * only when you need to enter/exit terminal mode, read keys, or query
 * terminal capabilities.
 *
 * The root `@garazyk/tui` module exports only pure types and functions
 * with no Deno I/O dependencies.
 *
 * @module tui/runtime
 */

// Terminal mode — from renderer.ts
export {
  enterTerminalMode,
  exitTerminalMode,
  writeToTerminal,
  isTerminal,
  getTerminalSize,
  getCurrentTheme,
  setCurrentTheme,
} from "./renderer.ts";

/** Whether the NO_COLOR environment variable is set. */
export const NO_COLOR: boolean = Deno.env.get("NO_COLOR") !== undefined;

// Key reading — from input.ts
export {
  readKeys,
} from "./input.ts";

/** Terminal logging utilities with color support and NO_COLOR awareness. @module logging */
import {
  blue,
  bold,
  cyan,
  green,
  red,
  yellow,
} from "@std/fmt/colors";

/** Log levels for controlling output verbosity. */
export type LogLevel = "debug" | "info" | "ok" | "warn" | "error";

/** Logger configuration. */
export interface LoggerOptions {
  /** Enable verbose (debug) logging. Defaults to false. */
  verbose?: boolean;
  /** Suppress non-error output. Defaults to false. */
  quiet?: boolean;
}

let _verbose = false;
let _quiet = false;

/** Initialize the global logger configuration. */
export function initLogger(options: LoggerOptions = {}): void {
  _verbose = options.verbose ?? false;
  _quiet = options.quiet ?? false;
}

/** Log a debug message (only shown if verbose is true). */
export function logDebug(message: string): void {
  if (_verbose && !_quiet) {
    console.error(`${blue("[DEBUG]")} ${message}`);
  }
}

/** Log an informational message. */
export function logInfo(message: string): void {
  if (!_quiet) {
    console.error(`${cyan("[INFO]")}  ${message}`);
  }
}

/** Log a success message. */
export function logOk(message: string): void {
  if (!_quiet) {
    console.error(`${green("[OK]")}    ${message}`);
  }
}

/** Log a warning message. */
export function logWarn(message: string): void {
  if (!_quiet) {
    console.error(`${yellow("[WARN]")}  ${message}`);
  }
}

/** Log an error message. */
export function logError(message: string): void {
  console.error(`${red("[ERROR]")} ${message}`);
}

/** Log a fatal error and exit the process. */
export function errorExit(message: string, code = 1): never {
  logError(message);
  Deno.exit(code);
}

/** Print a bold header (stderr). */
export function logHeader(message: string): void {
  if (!_quiet) {
    console.error(bold(message));
  }
}

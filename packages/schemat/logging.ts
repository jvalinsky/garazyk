/** Terminal logging utilities with color support and NO_COLOR awareness. @module logging */
import {
  blue,
  bold,
  cyan,
  green,
  red,
  yellow,
} from "@std/fmt/colors";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Log levels for controlling output verbosity. */
export type LogLevel = "debug" | "info" | "ok" | "warn" | "error";

/** Logger configuration. */
export interface LoggerOptions {
  /** Enable verbose (debug) logging. Defaults to false. */
  verbose?: boolean;
  /** Suppress non-error output. Defaults to false. */
  quiet?: boolean;
}

/** Output sink for log messages. */
export interface LoggerOutput {
  /** Write a formatted message. */
  write(message: string): void;
}

/** Injectable logger interface. */
export interface Logger {
  debug(message: string): void;
  info(message: string): void;
  ok(message: string): void;
  warn(message: string): void;
  error(message: string): void;
  header(message: string): void;
}

// ---------------------------------------------------------------------------
// ConsoleLogger
// ---------------------------------------------------------------------------

/** Console-based logger implementation with configurable output sink. */
export class ConsoleLogger implements Logger {
  #verbose: boolean;
  #quiet: boolean;
  #output: LoggerOutput;

  constructor(opts: LoggerOptions = {}, output?: LoggerOutput) {
    this.#verbose = opts.verbose ?? false;
    this.#quiet = opts.quiet ?? false;
    this.#output = output ?? { write: (msg: string) => console.error(msg) };
  }

  updateOptions(opts: LoggerOptions): void {
    if (opts.verbose !== undefined) this.#verbose = opts.verbose;
    if (opts.quiet !== undefined) this.#quiet = opts.quiet;
  }

  debug(message: string): void {
    if (this.#verbose && !this.#quiet) {
      this.#output.write(`${blue("[DEBUG]")} ${message}`);
    }
  }

  info(message: string): void {
    if (!this.#quiet) {
      this.#output.write(`${cyan("[INFO]")}  ${message}`);
    }
  }

  ok(message: string): void {
    if (!this.#quiet) {
      this.#output.write(`${green("[OK]")}    ${message}`);
    }
  }

  warn(message: string): void {
    if (!this.#quiet) {
      this.#output.write(`${yellow("[WARN]")}  ${message}`);
    }
  }

  error(message: string): void {
    this.#output.write(`${red("[ERROR]")} ${message}`);
  }

  header(message: string): void {
    if (!this.#quiet) {
      this.#output.write(bold(message));
    }
  }
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/**
 * Create a logger with the given options and output sink.
 *
 * Prefer this over the module-level convenience functions when you need
 * testability or multiple independent loggers.
 */
export function createLogger(
  opts?: LoggerOptions,
  output?: LoggerOutput,
): Logger {
  return new ConsoleLogger(opts, output);
}

// ---------------------------------------------------------------------------
// Module-level default logger (backward-compatible convenience API)
// ---------------------------------------------------------------------------

const _defaultLogger = new ConsoleLogger();

/** Initialize the global default logger configuration. */
export function initLogger(options: LoggerOptions = {}): void {
  _defaultLogger.updateOptions(options);
}

/** Log a debug message (only shown if verbose is true). */
export function logDebug(message: string): void {
  _defaultLogger.debug(message);
}

/** Log an informational message. */
export function logInfo(message: string): void {
  _defaultLogger.info(message);
}

/** Log a success message. */
export function logOk(message: string): void {
  _defaultLogger.ok(message);
}

/** Log a warning message. */
export function logWarn(message: string): void {
  _defaultLogger.warn(message);
}

/** Log an error message. */
export function logError(message: string): void {
  _defaultLogger.error(message);
}

/** Print a bold header (stderr). */
export function logHeader(message: string): void {
  _defaultLogger.header(message);
}

/** Log a fatal error and exit the process. */
export function errorExit(message: string, code = 1): never {
  _defaultLogger.error(message);
  Deno.exit(code);
}

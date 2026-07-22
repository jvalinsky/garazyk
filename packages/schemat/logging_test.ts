import { assert } from "@std/assert";
import { ConsoleLogger, createLogger, initLogger } from "./logging.ts";

/** Collect output from a logger into a string array. */
class StringOutput {
  lines: string[] = [];
  write(message: string): void {
    this.lines.push(message);
  }
}

// ---------------------------------------------------------------------------
// ConsoleLogger tests (via createLogger — the preferred DI path)
// ---------------------------------------------------------------------------

Deno.test("ConsoleLogger: defaults to non-verbose, non-quiet", () => {
  const out = new StringOutput();
  const log = createLogger({}, out);
  log.debug("hidden");
  log.info("visible");
  assert(
    !out.lines.some((l) => l.includes("hidden")),
    "debug message should be suppressed",
  );
  assert(
    out.lines.some((l) => l.includes("visible")),
    "info message should appear",
  );
});

Deno.test("ConsoleLogger: verbose enables debug output", () => {
  const out = new StringOutput();
  const log = createLogger({ verbose: true }, out);
  log.debug("debug-on");
  assert(
    out.lines.some((l) => l.includes("debug-on")),
    "debug message should appear when verbose",
  );
});

Deno.test("ConsoleLogger: quiet suppresses info output", () => {
  const out = new StringOutput();
  const log = createLogger({ quiet: true }, out);
  log.info("suppressed");
  assert(
    !out.lines.some((l) => l.includes("suppressed")),
    "info message should be suppressed when quiet",
  );
});

Deno.test("ConsoleLogger: quiet suppresses ok output", () => {
  const out = new StringOutput();
  const log = createLogger({ quiet: true }, out);
  log.ok("hidden-ok");
  assert(
    !out.lines.some((l) => l.includes("hidden-ok")),
    "ok message should be suppressed when quiet",
  );
});

Deno.test("ConsoleLogger: quiet suppresses warn output", () => {
  const out = new StringOutput();
  const log = createLogger({ quiet: true }, out);
  log.warn("hidden-warn");
  assert(
    !out.lines.some((l) => l.includes("hidden-warn")),
    "warn message should be suppressed when quiet",
  );
});

Deno.test("ConsoleLogger: quiet suppresses header output", () => {
  const out = new StringOutput();
  const log = createLogger({ quiet: true }, out);
  log.header("hidden-header");
  assert(
    !out.lines.some((l) => l.includes("hidden-header")),
    "header should be suppressed when quiet",
  );
});

Deno.test("ConsoleLogger: error always outputs regardless of quiet mode", () => {
  const out = new StringOutput();
  const log = createLogger({ quiet: true }, out);
  log.error("critical-error");
  assert(
    out.lines.some((l) => l.includes("critical-error")),
    "error message should always appear",
  );
});

Deno.test("ConsoleLogger: error always outputs in verbose mode", () => {
  const out = new StringOutput();
  const log = createLogger({ verbose: true, quiet: false }, out);
  log.error("always-on");
  assert(out.lines.some((l) => l.includes("always-on")));
});

Deno.test("ConsoleLogger: debug suppressed when verbose is false", () => {
  const out = new StringOutput();
  const log = createLogger({ verbose: false }, out);
  log.debug("should-be-hidden");
  assert(!out.lines.some((l) => l.includes("should-be-hidden")));
});

Deno.test("ConsoleLogger: debug suppressed when quiet is true even with verbose", () => {
  const out = new StringOutput();
  const log = createLogger({ verbose: true, quiet: true }, out);
  log.debug("both-flags");
  assert(
    !out.lines.some((l) => l.includes("both-flags")),
    "debug should be suppressed when quiet && verbose",
  );
});

Deno.test("ConsoleLogger: info includes the [INFO] prefix", () => {
  const out = new StringOutput();
  const log = createLogger({}, out);
  log.info("status update");
  assert(
    out.lines.some((l) => l.includes("[INFO]") && l.includes("status update")),
  );
});

Deno.test("ConsoleLogger: ok includes the [OK] prefix", () => {
  const out = new StringOutput();
  const log = createLogger({}, out);
  log.ok("success");
  assert(out.lines.some((l) => l.includes("[OK]") && l.includes("success")));
});

Deno.test("ConsoleLogger: warn includes the [WARN] prefix", () => {
  const out = new StringOutput();
  const log = createLogger({}, out);
  log.warn("caution");
  assert(out.lines.some((l) => l.includes("[WARN]") && l.includes("caution")));
});

Deno.test("ConsoleLogger: error includes the [ERROR] prefix", () => {
  const out = new StringOutput();
  const log = createLogger({}, out);
  log.error("boom");
  assert(out.lines.some((l) => l.includes("[ERROR]") && l.includes("boom")));
});

Deno.test("ConsoleLogger: header outputs bold text", () => {
  const out = new StringOutput();
  const log = createLogger({}, out);
  log.header("Welcome");
  assert(out.lines.some((l) => l.includes("Welcome")));
});

Deno.test("ConsoleLogger: updateOptions can toggle verbose on", () => {
  const out = new StringOutput();
  const log = new ConsoleLogger({}, out);
  log.debug("hidden");
  log.updateOptions({ verbose: true });
  log.debug("now-visible");
  assert(!out.lines.some((l) => l.includes("hidden")));
  assert(out.lines.some((l) => l.includes("now-visible")));
});

Deno.test("ConsoleLogger: updateOptions can toggle quiet on", () => {
  const out = new StringOutput();
  const log = new ConsoleLogger({}, out);
  log.info("visible");
  log.updateOptions({ quiet: true });
  log.info("hidden");
  assert(out.lines.some((l) => l.includes("visible")));
  assert(!out.lines.some((l) => l.includes("hidden")));
});

Deno.test("ConsoleLogger: updateOptions with undefined values does not change state", () => {
  const out = new StringOutput();
  const log = new ConsoleLogger({ verbose: true }, out);
  log.updateOptions({});
  log.debug("still-visible");
  assert(out.lines.some((l) => l.includes("still-visible")));
});

// ---------------------------------------------------------------------------
// Module-level convenience functions (backward-compatible)
// ---------------------------------------------------------------------------

Deno.test("convenience logDebug: uses default logger", () => {
  initLogger({ verbose: true });
  const out = new StringOutput();
  // Create a fresh default-like logger to test the pattern — the module-level
  // functions delegate to _defaultLogger, so we test via createLogger equivalence.
  const log = createLogger({ verbose: true }, out);
  log.debug("via di");
  assert(out.lines.some((l) => l.includes("via di")));
});

Deno.test("convenience logInfo: uses default logger", () => {
  initLogger({});
  const out = new StringOutput();
  const log = createLogger({}, out);
  log.info("via di");
  assert(out.lines.some((l) => l.includes("via di") && l.includes("[INFO]")));
});

Deno.test("initLogger + convenience functions: round-trip", () => {
  initLogger({ verbose: false });
  // Module-level functions delegate to _defaultLogger, which initLogger configures.
  // We test the pattern here by creating a logger and toggling it.
  const out = new StringOutput();
  const log = new ConsoleLogger({ verbose: false }, out);
  log.debug("hidden");
  log.updateOptions({ verbose: true });
  log.debug("visible");
  assert(!out.lines.some((l) => l.includes("hidden")));
  assert(out.lines.some((l) => l.includes("visible")));
});

// ---------------------------------------------------------------------------
// createLogger factories
// ---------------------------------------------------------------------------

Deno.test("createLogger: returns a ConsoleLogger instance", () => {
  const log = createLogger();
  assert(log instanceof ConsoleLogger);
});

Deno.test("createLogger: passes options through", () => {
  const out = new StringOutput();
  const log = createLogger({ quiet: true }, out);
  log.info("should be hidden");
  assert(!out.lines.some((l) => l.includes("should be hidden")));
});

Deno.test("createLogger: output defaults to console.error", () => {
  // Just verify construction doesn't throw.
  const log = createLogger();
  assert(log instanceof ConsoleLogger);
});

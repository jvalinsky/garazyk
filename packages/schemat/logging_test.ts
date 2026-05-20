import { assert, assertEquals } from "@std/assert";
import {
  initLogger,
  logDebug,
  logError,
  logInfo,
  logOk,
  logWarn,
} from "./logging.ts";

/** Capture console.error output during a test callback. */
function captureStderr(fn: () => void): string {
  const original = console.error;
  let output = "";
  console.error = (...args: unknown[]) => {
    output += args.map(String).join(" ") + "\n";
  };
  try {
    fn();
  } finally {
    console.error = original;
  }
  return output;
}

Deno.test("initLogger: defaults to non-verbose, non-quiet", () => {
  // Reset to defaults and verify that debug is suppressed and info is shown.
  initLogger({});
  const output = captureStderr(() => {
    logDebug("hidden");
    logInfo("visible");
  });
  assert(!output.includes("hidden"), "debug message should be suppressed");
  assert(output.includes("visible"), "info message should appear");
});

Deno.test("initLogger: verbose enables debug output", () => {
  initLogger({ verbose: true });
  const output = captureStderr(() => {
    logDebug("debug-on");
  });
  assert(output.includes("debug-on"), "debug message should appear when verbose");
});

Deno.test("initLogger: quiet suppresses info output", () => {
  initLogger({ quiet: true });
  const output = captureStderr(() => {
    logInfo("suppressed");
  });
  assert(!output.includes("suppressed"), "info message should be suppressed when quiet");
});

Deno.test("initLogger: quiet suppresses ok output", () => {
  initLogger({ quiet: true });
  const output = captureStderr(() => {
    logOk("hidden-ok");
  });
  assert(!output.includes("hidden-ok"), "ok message should be suppressed when quiet");
});

Deno.test("initLogger: quiet suppresses warn output", () => {
  initLogger({ quiet: true });
  const output = captureStderr(() => {
    logWarn("hidden-warn");
  });
  assert(!output.includes("hidden-warn"), "warn message should be suppressed when quiet");
});

Deno.test("logError: always outputs regardless of quiet mode", () => {
  initLogger({ quiet: true });
  const output = captureStderr(() => {
    logError("critical-error");
  });
  assert(output.includes("critical-error"), "error message should always appear");
});

Deno.test("logError: always outputs in verbose mode", () => {
  initLogger({ verbose: true, quiet: false });
  const output = captureStderr(() => {
    logError("always-on");
  });
  assert(output.includes("always-on"));
});

Deno.test("logDebug: is suppressed when verbose is false", () => {
  initLogger({ verbose: false });
  const output = captureStderr(() => {
    logDebug("should-be-hidden");
  });
  assert(!output.includes("should-be-hidden"));
});

Deno.test("logDebug: is suppressed when quiet is true even with verbose", () => {
  initLogger({ verbose: true, quiet: true });
  const output = captureStderr(() => {
    logDebug("both-flags");
  });
  assert(!output.includes("both-flags"), "debug should be suppressed when quiet && verbose");
});

Deno.test("logInfo: includes the [INFO] prefix", () => {
  initLogger({});
  const output = captureStderr(() => {
    logInfo("status update");
  });
  assert(output.includes("[INFO]"), "should include info prefix");
  assert(output.includes("status update"));
});

Deno.test("logOk: includes the [OK] prefix", () => {
  initLogger({});
  const output = captureStderr(() => {
    logOk("success");
  });
  assert(output.includes("[OK]"), "should include ok prefix");
  assert(output.includes("success"));
});

Deno.test("logWarn: includes the [WARN] prefix", () => {
  initLogger({});
  const output = captureStderr(() => {
    logWarn("caution");
  });
  assert(output.includes("[WARN]"), "should include warn prefix");
  assert(output.includes("caution"));
});

Deno.test("logError: includes the [ERROR] prefix", () => {
  initLogger({});
  const output = captureStderr(() => {
    logError("boom");
  });
  assert(output.includes("[ERROR]"), "should include error prefix");
  assert(output.includes("boom"));
});

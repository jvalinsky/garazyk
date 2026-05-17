#!/usr/bin/env -S deno run -A
import { parseArgs } from "@std/cli/parse-args";
import { runDashboardTui } from "./tui.ts";

/** Options for the dashboard CLI entry point. */
export interface DashboardCliOptions {
  /** Argument vector. Defaults to Deno.args. */
  args?: string[];
}

/** Run the dashboard command line tool. */
export async function runDashboardCli(
  options: DashboardCliOptions = {},
): Promise<void> {
  const parsed = parseArgs(options.args ?? Deno.args, {
    alias: {
      h: "help",
    },
    boolean: ["help", "once"],
    string: ["root", "interval"],
  });

  const command = String(parsed._[0] ?? "tui");

  if (parsed.help) {
    console.log(helpText());
    return;
  }

  const rootDir = typeof parsed.root === "string" ? parsed.root : undefined;

  switch (command) {
    case "tui":
      await runDashboardTui({
        rootDir,
        intervalMs: parseOptionalInteger(parsed.interval, "interval"),
        once: parsed.once,
      });
      return;
    case "status":
      await runDashboardTui({
        rootDir,
        once: true,
      });
      return;
    default:
      throw new Error(`Unknown dashboard command: ${command}`);
  }
}

function parseOptionalInteger(
  value: unknown,
  label: string,
): number | undefined {
  if (value === undefined) return undefined;
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) throw new Error(`Invalid ${label}: ${value}`);
  return parsed;
}

function helpText(): string {
  return `Garazyk scenario dashboard

Usage:
  deno run -A jsr:@garazyk/dashboard/cli [command] [options]

Commands:
  tui         Open the terminal dashboard (default)
  status      Print one terminal dashboard frame

Options:
  --root DIR       Garazyk checkout root, defaults to GARAZYK_ROOT or cwd
  --interval MS    TUI refresh interval, defaults to 2000
  --once           Render one TUI frame and exit
  -h, --help       Show this help
`;
}

if (import.meta.main) {
  try {
    await runDashboardCli();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}

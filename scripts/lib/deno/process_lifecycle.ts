import { red, yellow } from "@std/fmt/colors";
import type { RunnerArgs } from "./run_scenarios_types.ts";

export interface ProcessLifecycleContext {
  runId: string;
  diagnosticsDir: string;
}

export interface ProcessLifecycleOptions {
  args: Pick<RunnerArgs, "binary" | "keepRunning" | "teardown" | "noSetup">;
  context: ProcessLifecycleContext;
  stopLocalNetwork: (options: {
    useBinary: boolean;
    runId: string;
    diagnosticsDir: string;
    collectDiagnostics?: boolean;
  }) => Promise<void>;
}

export interface ProcessLifecycle {
  markNetworkStarted(): void;
  stopIfNeeded(collect?: boolean): Promise<void>;
  installSignalHandlers(): void;
  waitForShutdownSignal(): Promise<void>;
  finalizeRun(options: {
    results: Array<{ result: { failed: number } }>;
    fatalError: unknown;
    collectDiagnostics: () => Promise<void>;
  }): Promise<void>;
  scheduleDrainTimeout(timeoutMs?: number): number;
}

export function createProcessLifecycle(options: ProcessLifecycleOptions): ProcessLifecycle {
  let networkStarted = false;

  const stopIfNeeded = async (collect = false) => {
    if (!networkStarted || options.args.keepRunning) return;
    try {
      await options.stopLocalNetwork({
        useBinary: options.args.binary,
        runId: options.context.runId,
        diagnosticsDir: options.context.diagnosticsDir,
        collectDiagnostics: collect,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(red(`Error stopping local network: ${message}`));
    } finally {
      networkStarted = false;
    }
  };

  const installSignalHandlers = () => {
    const handleSignal = async () => {
      console.log(yellow("\nInterrupt received. Stopping gracefully..."));
      try {
        await stopIfNeeded(true);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error(red(`Failed to stop network on signal: ${message}`));
      }
      Deno.exit(130);
    };
    Deno.addSignalListener("SIGINT", handleSignal);
    Deno.addSignalListener("SIGTERM", handleSignal);
  };

  const waitForShutdownSignal = () => {
    return new Promise<void>((resolve) => {
      Deno.addSignalListener("SIGINT", () => resolve());
      Deno.addSignalListener("SIGTERM", () => resolve());
    });
  };

  const finalizeRun = async (finalizeOptions: {
    results: Array<{ result: { failed: number } }>;
    fatalError: unknown;
    collectDiagnostics: () => Promise<void>;
  }) => {
    const shouldCollect = finalizeOptions.results.some(({ result }) => result.failed > 0) ||
      finalizeOptions.fatalError;
    if (shouldCollect) {
      await finalizeOptions.collectDiagnostics();
      console.log(`Diagnostics: ${options.context.diagnosticsDir}`);
    }
    if (options.args.teardown || (!options.args.noSetup && !options.args.keepRunning)) {
      await stopIfNeeded(false);
    }
  };

  const scheduleDrainTimeout = (timeoutMs = 5000) => {
    const drainTimeout = setTimeout(() => {
      console.warn(`Event loop did not drain within ${timeoutMs / 1000}s after cleanup, forcing exit`);
      Deno.exit(0);
    }, timeoutMs);
    // In Deno, setTimeout returns a number. Use Deno.unrefTimer to prevent
    // the timeout from keeping the event loop alive — if the loop drains
    // naturally, this process exits before the callback fires.
    Deno.unrefTimer(drainTimeout);
    return drainTimeout;
  };

  return {
    markNetworkStarted() {
      networkStarted = true;
    },
    stopIfNeeded,
    installSignalHandlers,
    waitForShutdownSignal,
    finalizeRun,
    scheduleDrainTimeout,
  };
}

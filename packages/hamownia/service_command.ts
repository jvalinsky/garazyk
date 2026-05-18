/**
 * CLI command for managing local ATProto binary services.
 * @module service_command
 */

import { parseArgs } from "@std/cli/parse-args";
import { join } from "@std/path";
import { initRunDir, repoRoot } from "@garazyk/schemat/runtime";
import {
  initLogger,
  logError,
  logInfo,
  logHeader,
  logOk,
} from "@garazyk/schemat";
import {
  startBinaryServices,
  stopBinaryServices,
  printBinaryStatusReport,
  BINARY_SERVICES,
  type BinaryServiceName,
} from "./binary_services.ts";

/** Entry point for the service management CLI. */
export async function serviceCommandMain(argv: string[]) {
  const flags = parseArgs(argv, {
    boolean: ["verbose", "quiet", "help", "all"],
    string: ["service"],
    alias: { h: "help", v: "verbose", q: "quiet", s: "service", a: "all" },
  });

  if (flags.help) {
    console.log(`Usage: scripts/manage_services.ts <command> [options]

Commands:
  start     Start binary services
  stop      Stop binary services
  restart   Restart binary services
  status    Show service status report
  logs      Show or follow service logs
  reseed    Stop services, wipe data, and restart with fresh data

Options:
  -s, --service SVC    Target specific service (plc, pds, relay, appview, chat, video)
  -a, --all            Target all known services (default)
  -v, --verbose        Enable verbose logging
  -q, --quiet          Suppress non-error output
  --help               Show this help
`);
    return;
  }

  initLogger({ verbose: flags.verbose, quiet: flags.quiet });

  const command = flags._[0] as string;
  const ctx = initRunDir();
  const root = await repoRoot();

  const targetServices = flags.service
    ? [flags.service as BinaryServiceName]
    : (Object.keys(BINARY_SERVICES) as BinaryServiceName[]);

  switch (command) {
    case "start":
      await startBinaryServices(ctx, { services: targetServices });
      break;
    case "stop":
      await stopBinaryServices(ctx, targetServices);
      break;
    case "restart":
      await stopBinaryServices(ctx, targetServices);
      await new Promise((r) => setTimeout(r, 2000));
      await startBinaryServices(ctx, { services: targetServices });
      break;
    case "status":
      await printBinaryStatusReport(ctx);
      break;
    case "reseed": {
      logInfo("Reseeding local network...");
      await stopBinaryServices(ctx, targetServices);
      
      const dataDir = join(ctx.runDir, "data");
      try {
        logInfo(`Wiping data directory: ${dataDir}`);
        await Deno.remove(dataDir, { recursive: true });
      } catch { /* ignore */ }
      
      await startBinaryServices(ctx, { services: targetServices });
      
      logInfo("Seeding test accounts...");
      const seedProc = new Deno.Command("deno", {
        args: ["run", "-A", join(root, "scripts", "seed_full_suite.ts")],
        env: {
          PDS_URL: "http://127.0.0.1:2583",
          CHAT_URL: "http://127.0.0.1:2585",
        }
      });
      await seedProc.output();
      logOk("Network reseeded and seeded successfully.");
      break;
    }
    case "logs": {
      const service = flags.service || "plc";
      const logFile = join(ctx.logDir, `${service}.log`);
      logInfo(`Following logs for ${service} (Ctrl+C to stop)...`);
      const proc = new Deno.Command("tail", {
        args: ["-f", logFile],
        stdout: "inherit",
        stderr: "inherit",
      });
      await proc.spawn().status;
      break;
    }
    default:
      logError(`Unknown command: ${command}`);
      Deno.exit(1);
  }
}

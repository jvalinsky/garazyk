import { Command, EnumType } from "@cliffy/command";
import { join } from "@std/path";
import { initRunDir, repoRoot } from "@garazyk/schemat/runtime";
import { initLogger, logInfo, logOk } from "@garazyk/schemat";
import {
  BINARY_SERVICES,
  printBinaryStatusReport,
  startBinaryServices,
  stopBinaryServices,
  type BinaryServiceName,
} from "../binary_services.ts";
import { psCommand } from "./ps.ts";
import { topologyCommand } from "./topology.ts";

const SERVICE_NAMES = Object.keys(BINARY_SERVICES) as BinaryServiceName[];
const serviceType = new EnumType(SERVICE_NAMES);

function resolveServices(service?: BinaryServiceName[]): BinaryServiceName[] {
  return service && service.length > 0 ? service : SERVICE_NAMES;
}

function init(options: { verbose?: boolean; quiet?: boolean }) {
  initLogger({ verbose: options.verbose, quiet: options.quiet });
  return initRunDir();
}

interface ActionWithVerboseQuiet {
  verbose?: boolean;
  quiet?: boolean;
}

interface StartStopActionOptions extends ActionWithVerboseQuiet {
  service?: BinaryServiceName[];
}

interface LogsActionOptions extends ActionWithVerboseQuiet {
  service: BinaryServiceName;
}

const startCmd = new Command()
  .description("Start services.")
  .alias("up")
  .type("service", serviceType)
  .option("-s, --service <name:service>", "Target specific service.", { collect: true })
  .action(async ({ service, verbose, quiet }: StartStopActionOptions) => {
    const ctx = init({ verbose, quiet });
    await startBinaryServices(ctx, { services: resolveServices(service) });
  });

const stopCmd = new Command()
  .description("Stop services.")
  .alias("down")
  .type("service", serviceType)
  .option("-s, --service <name:service>", "Target specific service.", { collect: true })
  .action(async ({ service, verbose, quiet }: StartStopActionOptions) => {
    init({ verbose, quiet });
    const ctx = initRunDir();
    await stopBinaryServices(ctx, resolveServices(service));
  });

const restartCmd = new Command()
  .description("Restart services.")
  .type("service", serviceType)
  .option("-s, --service <name:service>", "Target specific service.", { collect: true })
  .action(async ({ service, verbose, quiet }: StartStopActionOptions) => {
    const ctx = init({ verbose, quiet });
    const targets = resolveServices(service);
    await stopBinaryServices(ctx, targets);
    await new Promise((r) => setTimeout(r, 2000));
    await startBinaryServices(ctx, { services: targets });
  });

const statusCmd = new Command()
  .description("Show service health status.")
  .action(async () => {
    init({});
    const ctx = initRunDir();
    await printBinaryStatusReport(ctx);
  });

const logsCmd = new Command()
  .description("Follow service logs.")
  .type("service", serviceType)
  .option("-s, --service <name:service>", "Service to tail.", { default: "plc" })
  .action(async ({ service, verbose, quiet }: LogsActionOptions) => {
    init({ verbose, quiet });
    const ctx = initRunDir();
    const logFile = join(ctx.logDir, `${service}.log`);
    logInfo(`Following logs for ${service} (Ctrl+C to stop)...`);
    const proc = new Deno.Command("tail", {
      args: ["-f", logFile],
      stdout: "inherit",
      stderr: "inherit",
    });
    await proc.spawn().status;
  });

const reseedCmd = new Command()
  .description("Wipe data and restart with fresh seed.")
  .type("service", serviceType)
  .option("-s, --service <name:service>", "Target specific service.", { collect: true })
  .action(async ({ service, verbose, quiet }: StartStopActionOptions) => {
    const ctx = init({ verbose, quiet });
    const root = await repoRoot();
    const targets = resolveServices(service);

    logInfo("Reseeding local network...");
    await stopBinaryServices(ctx, targets);

    const dataDir = join(ctx.runDir, "data");
    try {
      logInfo(`Wiping data directory: ${dataDir}`);
      await Deno.remove(dataDir, { recursive: true });
    } catch { /* ignore */ }

    await startBinaryServices(ctx, { services: targets });

    logInfo("Seeding test accounts...");
    const seedProc = new Deno.Command("deno", {
      args: ["run", "-A", join(root, "scripts", "seed_full_suite.ts")],
      env: {
        PDS_URL: "http://127.0.0.1:2583",
        CHAT_URL: "http://127.0.0.1:2585",
      },
    });
    await seedProc.output();
    logOk("Network reseeded and seeded successfully.");
  });

export const serviceCommand = new Command()
  .description("Manage local ATProto service lifecycle.\n\n" +
    "Start, stop, restart, and monitor local binary services " +
    "(PLC, PDS, Relay, AppView, Chat, Video).")
  .command("start", startCmd)
  .command("stop", stopCmd)
  .command("restart", restartCmd)
  .command("status", statusCmd)
  .command("logs", logsCmd)
  .command("reseed", reseedCmd)
  .command("ps", psCommand)
  .command("topology", topologyCommand);

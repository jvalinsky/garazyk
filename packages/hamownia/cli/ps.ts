import { Command } from "@cliffy/command";
import { Table } from "@cliffy/table";
import { initLogger, logInfo } from "@garazyk/schemat";
import {
  initRunDir,
  SERVICE_PORTS,
  serviceUrl,
} from "@garazyk/schemat/runtime";
import {
  BINARY_SERVICES,
  type BinaryServiceName,
  getBinaryServiceStatus,
} from "../binary_services.ts";
import { bold, cyan, green, red, yellow } from "@std/fmt/colors";

interface PsOptions {
  verbose?: boolean;
  quiet?: boolean;
  all?: boolean;
}

function statusStr(running: boolean, healthy: boolean | undefined): string {
  if (!running) return red("Stopped");
  return healthy ? green("Running") : yellow("Running");
}

function healthStr(running: boolean, healthy: boolean | undefined): string {
  if (!running) return "-";
  return healthy ? green("Healthy") : red("Unhealthy");
}

const ALL_SERVICES = Object.keys(BINARY_SERVICES) as BinaryServiceName[];

export const psCommand = new Command()
  .description(
    "List service status in a table.\n\n" +
      "Shows running state, health, PID, port, URL, and binary for each local ATProto service. " +
      "By default only running services are shown (like `docker ps`). Use --all to show everything.",
  )
  .option("-a, --all", "Show all services, not just running ones.")
  .action(async ({ verbose, quiet, all }: PsOptions) => {
    initLogger({ verbose, quiet });
    const ctx = initRunDir();
    const status = await getBinaryServiceStatus(ctx);

    const services = all
      ? ALL_SERVICES
      : ALL_SERVICES.filter((s) => status[s].running);

    if (services.length === 0) {
      logInfo("No services running. Use --all to see all configured services.");
      return;
    }

    new Table()
      .header([
        bold("NAME"),
        bold("STATUS"),
        bold("HEALTH"),
        bold("PID"),
        bold("PORT"),
        bold("URL"),
        bold("BINARY"),
      ])
      .body(
        services.map((name) => {
          const s = status[name];
          return [
            cyan(name.toUpperCase()),
            statusStr(s.running, s.healthy),
            healthStr(s.running, s.healthy),
            s.pid?.toString() ?? "-",
            String(SERVICE_PORTS[name]),
            serviceUrl(name),
            BINARY_SERVICES[name].binary,
          ];
        }),
      )
      .border(true)
      .render();

    if (verbose) {
      console.log("");
      console.log(bold("Setup Details:"));
      console.log(`  Run ID:       ${ctx.runId}`);
      console.log(`  Run Dir:      ${ctx.runDir}`);
      console.log(`  Data Dir:     ${ctx.runDir}/data`);
      console.log(`  Log Dir:      ${ctx.logDir}`);
      console.log(`  PID File:     ${ctx.pidFile}`);
      console.log(`  Base Dir:     ${ctx.baseDir}`);
      console.log(`  Compose Proj: ${ctx.composeProject}`);
    }
  });

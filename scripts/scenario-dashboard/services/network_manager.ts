/**
 * Network Manager — manages Docker Compose lifecycle for the local ATProto stack.
 * Wraps setup_local_network.sh / teardown_local_network.sh and adds
 * granular per-service control and health checking.
 */

import { join, fromFileUrl } from "$std/path/mod.ts";
import { ServiceStatus, ServiceStatusType } from "./types.ts";

const SCRIPTS_DIR = join(
  fromFileUrl(new URL("../../scenarios", import.meta.url)),
);

const KNOWN_SERVICES: Omit<ServiceStatus, "status" | "healthy">[] = [
  { name: "pds", label: "PDS", url: "http://localhost:2583", port: 2583 },
  { name: "plc", label: "PLC", url: "http://localhost:2582", port: 2582 },
  { name: "relay", label: "Relay", url: "http://localhost:2584", port: 2584 },
  { name: "appview", label: "AppView", url: "http://localhost:3200", port: 3200 },
  { name: "chat", label: "Chat", url: "http://localhost:2585", port: 2585 },
  { name: "pds2", label: "PDS2", url: "http://localhost:2587", port: 2587 },
  { name: "video", label: "Video", url: "http://localhost:2586", port: 2586 },
  { name: "ui", label: "Admin UI", url: "http://localhost:2590", port: 2590 },
];

class NetworkManager {
  private services: Map<string, ServiceStatus> = new Map();
  private healthInterval?: number;

  constructor() {
    for (const s of KNOWN_SERVICES) {
      this.services.set(s.name, { ...s, status: "stopped", healthy: false });
    }
    // Start background health checking, but not during build
    if (!Deno.args.includes("build")) {
      this.startHealthChecks();
    }
  }

  /**
   * Proactively look for running docker containers matching our services
   */
  private async discoverRunningServices(): Promise<void> {
    const projectDir = join(
      fromFileUrl(new URL("../../../docker/local-network", import.meta.url)),
    );
    const composeFile = join(projectDir, "docker-compose.yml");

    try {
      const command = new Deno.Command("docker", {
        args: ["compose", "ls", "--format", "json"],
      });
      const { stdout } = await command.output();
      const output = new TextDecoder().decode(stdout);
      if (!output.trim()) {
        // No compose projects at all, all should be stopped
        for (const name of this.services.keys()) {
          this.updateStatus(name, "stopped");
        }
        return;
      }

      const projects = JSON.parse(output) as Array<{
        Name: string;
        Status: string;
        ConfigFiles: string;
      }>;

      // Find all projects using our e2e naming convention or compose file
      // In scenario mode, projects are named garazyk-e2e-<id>
      const relevantProjects = projects.filter((p) => 
        p.Name.startsWith("garazyk-e2e-") ||
        p.ConfigFiles?.includes(composeFile)
      );

      if (relevantProjects.length === 0) {
        for (const name of this.services.keys()) {
          this.updateStatus(name, "stopped");
        }
        return;
      }

      // Track which services we found across all relevant projects
      const foundServices = new Set<string>();

      for (const project of relevantProjects) {
        const psCommand = new Deno.Command("docker", {
          args: ["compose", "-p", project.Name, "ps", "--format", "json"],
        });
        const { stdout: psStdout } = await psCommand.output();
        const psOutput = new TextDecoder().decode(psStdout);
        
        const containers = psOutput.trim().split("\n").filter(l => l.trim()).map(line => {
          try { 
            return JSON.parse(line) as {
              Service: string;
              State: string;
            }; 
          } catch { 
            return null; 
          }
        }).filter((c): c is NonNullable<typeof c> => c !== null);

        for (const container of containers) {
          const serviceName = container.Service;
          // Map local-pds to pds, local-chat to chat etc.
          let mappedName = serviceName.replace("local-", "");

          if (this.services.has(mappedName)) {
            foundServices.add(mappedName);
            if (container.State === "running" || container.State === "starting") {
              this.updateStatus(mappedName, container.State === "running" ? "running" : "starting");
            } else {
              this.updateStatus(mappedName, "stopped");
            }
          }
        }
      }

      // Any service NOT found in any running project is stopped
      for (const name of this.services.keys()) {
        if (!foundServices.has(name)) {
          this.updateStatus(name, "stopped");
        }
      }
    } catch (e) {
      console.error("[network] discovery failed:", e);
    }
  }

  async startAll(opts?: { pds2?: boolean }): Promise<void> {
    const scriptPath = join(SCRIPTS_DIR, "setup_local_network.sh");
    const args = [scriptPath];
    if (opts?.pds2) args.push("--pds2");

    // Mark services as starting
    for (const [name, s] of this.services) {
      if (opts?.pds2 || name !== "pds2") {
        this.updateStatus(name, "starting");
      }
    }

    try {
      const command = new Deno.Command("bash", {
        args,
        stdout: "inherit",
        stderr: "inherit",
      });
      const { code } = await command.output();
      if (code !== 0) {
        throw new Error(`Docker setup failed with exit code ${code}`);
      }

      // Immediately run a health check to update status
      await this.healthCheck();
    } catch (e) {
      // Mark all as error
      for (const [name] of this.services) {
        if (this.services.get(name)?.status === "starting") {
          this.updateStatus(name, "error");
        }
      }
      throw e;
    }
  }

  async stopAll(): Promise<void> {
    const scriptPath = join(SCRIPTS_DIR, "teardown_local_network.sh");

    try {
      const command = new Deno.Command("bash", {
        args: [scriptPath],
        stdout: "inherit",
        stderr: "inherit",
      });
      await command.output();
    } finally {
      // Discovery will pick up that they are gone
      await this.discoverRunningServices();
    }
  }

  async healthCheck(): Promise<Record<string, ServiceStatus>> {
    // Sync with Docker first
    await this.discoverRunningServices();

    const results: Record<string, ServiceStatus> = {};

    for (const [name, s] of this.services) {
      // Only health check if it's supposed to be running or starting
      if (s.status === "stopped") {
        results[name] = s;
        continue;
      }

      try {
        let url = "";
        const headers: Record<string, string> = {};

        switch (name) {
          case "relay":
            url = `${s.url}/api/relay/health`;
            break;
          case "pds":
          case "pds2":
            url = `${s.url}/xrpc/com.atproto.server.describeServer`;
            break;
          case "appview":
            url = `${s.url}/admin/backfill/status`;
            headers["Authorization"] = "Bearer localdevadmin";
            break;
          case "plc":
            url = `${s.url}/_health`;
            break;
          case "ui":
            url = `${s.url}/admin`;
            break;
          default:
            url = `${s.url}/_health`;
        }

        const controller = new AbortController();
        const id = setTimeout(() => controller.abort(), 3000);
        const resp = await fetch(url, { 
          signal: controller.signal,
          headers: Object.keys(headers).length > 0 ? headers : undefined
        });
        clearTimeout(id);

        const healthy = resp.ok;
        if (healthy && (s.status === "error" || s.status === "starting")) {
          this.updateStatus(name, "running");
        }
        
        const current = this.services.get(name) || s;
        const updated = { ...current, healthy };
        this.services.set(name, updated);
        results[name] = updated;
      } catch (e) {
        // If it was running but now fails, it's still "running" but unhealthy
        const current = this.services.get(name) || s;
        const updated = { ...current, healthy: false };
        this.services.set(name, updated);
        results[name] = updated;
      }
    }

    return results;
  }

  getStatus(): Record<string, ServiceStatus> {
    return Object.fromEntries(this.services);
  }

  getServiceStatus(name: string): ServiceStatus | undefined {
    return this.services.get(name);
  }

  private updateStatus(name: string, status: ServiceStatusType) {
    const s = this.services.get(name);
    if (s && s.status !== status) {
      this.services.set(name, { ...s, status, healthy: status === "running" ? s.healthy : false });
    }
  }

  private startHealthChecks() {
    if (this.healthInterval) return;
    this.healthInterval = setInterval(() => this.healthCheck(), 10000);
    // Trigger first one immediately
    this.healthCheck().catch(() => {});
  }

  private stopHealthChecks() {
    if (this.healthInterval) {
      clearInterval(this.healthInterval);
      this.healthInterval = undefined;
    }
  }

  async streamLogs(service: string): Promise<AsyncIterable<string>> {
    const projectDir = join(
      fromFileUrl(new URL("../../../docker/local-network", import.meta.url)),
    );

    const command = new Deno.Command("docker", {
      args: ["compose", "-f", `${projectDir}/docker-compose.yml`, "logs", "-f", "--no-log-prefix", service],
      stdout: "piped",
      stderr: "piped",
    });

    const process = command.spawn();

    async function* generate() {
      const reader = process.stdout.getReader();
      const decoder = new TextDecoder();
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          yield decoder.decode(value);
        }
      } finally {
        reader.releaseLock();
        process.kill();
      }
    }

    return generate();
  }
}

/** Global network manager singleton */
export const networkManager = new NetworkManager();

/**
 * Network Manager — manages Docker Compose lifecycle for the local ATProto stack.
 * Wraps setup_local_network.sh / teardown_local_network.sh and adds
 * granular per-service control and health checking.
 */

import { join, fromFileUrl } from "$std/path/mod.ts";
import { ServiceStatus, ServiceStatusType } from "./types.ts";
import { runManager } from "./run_manager.ts";

const SCRIPTS_DIR = join(
  fromFileUrl(new URL("../../scenarios", import.meta.url)),
);

class NetworkManager {
  private services: Map<string, ServiceStatus> = new Map();
  private healthInterval?: number;

  constructor() {
    // Start background health checking, but not during build
    if (!Deno.args.includes("build")) {
      this.startHealthChecks();
    }
  }

  async startAll(opts?: { pds2?: boolean }): Promise<void> {
    const scriptPath = join(SCRIPTS_DIR, "setup_local_network.sh");
    const args = [scriptPath];
    if (opts?.pds2) args.push("--pds2");

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

      await this.healthCheck();
    } catch (e) {
      console.error("[network] startAll failed:", e);
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
      await this.discoverRunningServices();
    }
  }

  getServiceStatus(name: string): ServiceStatus | undefined {
    return this.services.get(name);
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

  async getContainerStats(): Promise<Record<string, { cpu: string; mem: string }>> {
    const stats: Record<string, { cpu: string; mem: string }> = {};

    try {
      // Execute docker stats for all running containers
      const command = new Deno.Command("docker", {
        args: ["stats", "--no-stream", "--format", "json"],
      });
      const { stdout } = await command.output();
      const output = new TextDecoder().decode(stdout);
      
      const lines = output.trim().split("\n").filter(l => l.trim());
      for (const line of lines) {
        try {
          const data = JSON.parse(line);
          const name = data.Name;
          
          // Map container name to service name (e.g. garazyk-e2e-2026-05-14T...-plc-1 -> plc)
          // Look for patterns like *-<service>-1
          let serviceName = name;
          const match = name.match(/-(.+)-\d+$/);
          if (match) {
            serviceName = match[1];
          } else if (name.startsWith("local-")) {
            serviceName = name.replace("local-", "");
          }

          stats[serviceName] = {
            cpu: data.CPUPerc,
            mem: data.MemUsage,
          };
        } catch {
          continue;
        }
      }
    } catch (e) {
      console.error("[network] failed to get container stats:", e);
    }

    return stats;
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
        this.markAllStopped();
        return;
      }

      const projects = JSON.parse(output) as Array<{
        Name: string;
        Status: string;
        ConfigFiles: string;
      }>;

      const relevantProjects = projects.filter((p) => 
        p.Name.startsWith("garazyk-e2e-") ||
        p.ConfigFiles?.includes(composeFile)
      );

      if (relevantProjects.length === 0) {
        this.markAllStopped();
        return;
      }

      const foundServices = new Set<string>();

      for (const project of relevantProjects) {
        const psCommand = new Deno.Command("docker", {
          args: ["compose", "-p", project.Name, "ps", "--format", "json"],
        });
        const { stdout: psStdout } = await psCommand.output();
        const psOutput = new TextDecoder().decode(psStdout);
        
        const containers = psOutput.trim().split("\n").filter(l => l.trim()).map(line => {
          try { return JSON.parse(line); } catch { return null; }
        }).filter(c => c !== null);

        for (const container of containers) {
          const serviceName = container.Service;
          let mappedName = serviceName.replace("local-", "");
          foundServices.add(mappedName);
          
          if (!this.services.has(mappedName)) {
            // Dynamically add discovered service
            this.services.set(mappedName, {
              name: mappedName,
              label: mappedName.toUpperCase(),
              url: "", // Will be updated by health check if it's a known role
              port: 0,
              status: "stopped",
            });
          }

          if (container.State === "running" || container.State === "starting") {
            this.updateStatus(mappedName, container.State === "running" ? "running" : "starting");
          } else {
            this.updateStatus(mappedName, "stopped");
          }
        }
      }

      for (const name of this.services.keys()) {
        if (!foundServices.has(name)) {
          this.updateStatus(name, "stopped");
        }
      }
    } catch (e) {
      console.error("[network] discovery failed:", e);
    }
  }

  private markAllStopped() {
    for (const name of this.services.keys()) {
      this.updateStatus(name, "stopped");
    }
  }

  async healthCheck(): Promise<Record<string, ServiceStatus>> {
    await this.discoverRunningServices();

    const results: Record<string, ServiceStatus> = {};
    const activeRun = runManager.getActiveRun();
    
    // If we have an active run, we should have a manifest with health probes
    // TODO: Load manifest from activeRun.manifestPath if available

    for (const [name, s] of this.services) {
      if (s.status === "stopped") {
        results[name] = s;
        continue;
      }

      try {
        // Fallback to heuristic-based health checks if no manifest probes
        const healthUrl = this.getHealthUrl(name, s.url);
        if (!healthUrl) {
          results[name] = s;
          continue;
        }

        const controller = new AbortController();
        const id = setTimeout(() => controller.abort(), 3000);
        const resp = await fetch(healthUrl, { signal: controller.signal });
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
        const current = this.services.get(name) || s;
        const updated = { ...current, healthy: false };
        this.services.set(name, updated);
        results[name] = updated;
      }
    }

    return results;
  }

  private getHealthUrl(name: string, baseUrl: string): string | null {
    if (!baseUrl) {
      // Try to infer default local ports if url is missing
      const ports: Record<string, number> = {
        pds: 2583, plc: 2582, relay: 2584, appview: 3200, 
        chat: 2585, pds2: 2587, video: 2586, ui: 2590
      };
      if (ports[name]) baseUrl = `http://localhost:${ports[name]}`;
      else return null;
    }

    switch (name) {
      case "relay": return `${baseUrl}/api/relay/health`;
      case "pds":
      case "pds2": return `${baseUrl}/xrpc/com.atproto.server.describeServer`;
      case "appview": return `${baseUrl}/admin/backfill/status`;
      case "plc": return `${baseUrl}/_health`;
      default: return `${baseUrl}/_health`;
    }
  }

  getStatus(): Record<string, ServiceStatus> {
    return Object.fromEntries(this.services);
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
    this.healthCheck().catch(() => {});
  }
}

export const networkManager = new NetworkManager();

/**
 * Network Manager — manages Docker Compose lifecycle for the local ATProto stack.
 * Wraps setup_local_network.sh / teardown_local_network.sh and adds
 * granular per-service control and health checking.
 */

import { join, fromFileUrl } from "$std/path/mod.ts";
import { eventBus } from "./event_bus.ts";

export interface ServiceStatus {
  name: string;
  label: string;
  url: string;
  port: number;
  status: "running" | "stopped" | "starting" | "error";
  healthy?: boolean;
}

const SCRIPTS_DIR = join(
  fromFileUrl(new URL("../../scenarios", import.meta.url)),
);

const KNOWN_SERVICES: Omit<ServiceStatus, "status" | "healthy">[] = [
  { name: "pds", label: "PDS", url: "http://localhost:2583", port: 2583 },
  { name: "plc", label: "PLC", url: "http://localhost:2582", port: 2582 },
  { name: "relay", label: "Relay", url: "http://localhost:2584", port: 2584 },
  { name: "appview", label: "AppView", url: "http://localhost:2583", port: 2583 },
  { name: "pds2", label: "Chat (PDS2)", url: "http://localhost:2585", port: 2585 },
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

      // Mark core services as running (we'll verify with health checks)
      for (const [name, s] of this.services) {
        if (opts?.pds2 || name !== "pds2") {
          this.updateStatus(name, "running");
        }
      }

      // Start health checking
      this.startHealthChecks();
    } catch (e) {
      // Mark all as error
      for (const [name] of this.services) {
        this.updateStatus(name, "error");
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
      for (const [name] of this.services) {
        this.updateStatus(name, "stopped");
      }
      this.stopHealthChecks();
    }
  }

  async healthCheck(): Promise<Record<string, ServiceStatus>> {
    const results: Record<string, ServiceStatus> = {};

    for (const [name, s] of this.services) {
      if (s.status !== "running") {
        results[name] = { ...s };
        continue;
      }

      try {
        const url = name === "relay"
          ? `${s.url}/api/relay/health`
          : name === "pds" || name === "pds2"
          ? `${s.url}/xrpc/com.atproto.server.describeServer`
          : `${s.url}/_health`;

        const controller = new AbortController();
        const id = setTimeout(() => controller.abort(), 3000);
        const resp = await fetch(url, { signal: controller.signal });
        clearTimeout(id);

        const healthy = resp.ok;
        this.services.set(name, { ...s, healthy });
        results[name] = { ...s, healthy };
      } catch {
        this.services.set(name, { ...s, healthy: false });
        results[name] = { ...s, healthy: false };
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

  private updateStatus(name: string, status: ServiceStatus["status"]) {
    const s = this.services.get(name);
    if (s) {
      this.services.set(name, { ...s, status, healthy: status === "running" ? s.healthy : false });
      eventBus.emit({ type: "service_status", service: name, status, healthy: s.healthy });
    }
  }

  private startHealthChecks() {
    if (this.healthInterval) return;
    this.healthInterval = setInterval(() => this.healthCheck(), 10000);
  }

  private stopHealthChecks() {
    if (this.healthInterval) {
      clearInterval(this.healthInterval);
      this.healthInterval = undefined;
    }
  }

  async streamLogs(service: string): Promise<AsyncIterable<string>> {
    // Use docker compose logs -f for the service
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

/**
 * Network Manager — manages Docker Compose lifecycle for the local ATProto stack.
 * Wraps setup_local_network.sh / teardown_local_network.sh and adds
 * granular per-service control and health checking.
 *
 * When the Docker Engine API is available (Unix socket), uses direct
 * API calls instead of CLI subprocesses for container discovery, stats,
 * and log streaming. Falls back to CLI-based operations when the socket
 * is unavailable.
 *
 * @module network_manager
 */

import { join } from "@std/path";
import type { ServiceStatus, ServiceStatusType } from "./types.ts";
import {
  composeServiceName,
  type ContainerSummary,
  cpuPercent,
  createDockerClient,
  type DockerApiClient,
  formatMemory,
} from "@garazyk/laweta";
import {
  startLocalNetwork,
  stopLocalNetwork,
} from "@garazyk/hamownia/atproto-network";
import { ContainerEventWatcher, type WatcherEvent } from "@garazyk/laweta";
import { getDashboardPaths } from "../paths.ts";

/** Public network manager API used by routes, the web runtime, and the TUI. */
export interface NetworkManagerApi {
  startAll(opts?: { pds2?: boolean }): Promise<void>;
  stopAll(): Promise<void>;
  getServiceStatus(name: string): ServiceStatus | undefined;
  streamLogs(service: string): Promise<AsyncIterable<string>>;
  getContainerStats(): Promise<Record<string, { cpu: string; mem: string }>>;
  healthCheck(): Promise<Record<string, ServiceStatus>>;
  getStatus(): Record<string, ServiceStatus>;
  destroy(): void;
}

/** Manages Docker service lifecycle, health checks, container stats, and log streaming. */
class NetworkManager {
  private services: Map<string, ServiceStatus> = new Map();
  private healthInterval?: number;
  private dockerClient: DockerApiClient | null = null;
  private eventWatcher: ContainerEventWatcher | null = null;
  private eventUnsubscribe: (() => void) | null = null;

  constructor() {
    // Start background health checking, but not during build
    if (!Deno.args.includes("build")) {
      this.initDockerApi();
      this.startHealthChecks();
    }
  }

  /**
   * Initialize the Docker API client and event watcher.
   * If the Docker socket is unavailable, operations fall back to CLI.
   */
  private async initDockerApi(): Promise<void> {
    try {
      const client = await createDockerClient();
      if (client) {
        this.dockerClient = client;
        // Start event watcher for real-time container status updates
        const watcher = await ContainerEventWatcher.create();
        if (watcher) {
          this.eventWatcher = watcher;
          this.eventUnsubscribe = watcher.subscribe((event) => {
            this.handleWatcherEvent(event);
          });
        }
      }
    } catch {
      // Docker API not available — will use CLI fallbacks
    }
  }

  async startAll(opts?: { pds2?: boolean }): Promise<void> {
    try {
      await startLocalNetwork({
        withPds2: opts?.pds2,
        keepRunning: true,
      });

      await this.healthCheck();
    } catch (e) {
      console.error("[network] startAll failed:", e);
      throw e;
    }
  }

  async stopAll(): Promise<void> {
    try {
      await stopLocalNetwork({ keepRunning: false });
    } finally {
      await this.discoverRunningServices();
    }
  }

  getServiceStatus(name: string): ServiceStatus | undefined {
    return this.services.get(name);
  }

  async streamLogs(service: string): Promise<AsyncIterable<string>> {
    // Try Docker API first
    if (this.dockerClient) {
      try {
        const containers = await this.dockerClient.listContainers({
          label: [`com.docker.compose.service=${service}`],
        });
        if (containers.length > 0) {
          const id = containers[0].Id;
          return this.streamLogsViaAPI(id);
        }
      } catch {
        // Fall through to CLI
      }
    }

    // CLI fallback
    return this.streamLogsViaCLI(service);
  }

  async getContainerStats(): Promise<
    Record<string, { cpu: string; mem: string }>
  > {
    const stats: Record<string, { cpu: string; mem: string }> = {};

    // Try Docker API first
    if (this.dockerClient) {
      try {
        const containers = await this.dockerClient.listContainers({
          status: ["running"],
        });
        for (const container of containers) {
          try {
            const serviceName = this.resolveServiceName(container);
            const containerStats = await this.dockerClient.containerStats(
              container.Id,
            );
            stats[serviceName] = {
              cpu: `${cpuPercent(containerStats).toFixed(2)}%`,
              mem: formatMemory(containerStats),
            };
          } catch {
            continue;
          }
        }
        return stats;
      } catch {
        // Fall through to CLI
      }
    }

    // CLI fallback
    try {
      const command = new Deno.Command("docker", {
        args: ["stats", "--no-stream", "--format", "json"],
      });
      const { stdout } = await command.output();
      const output = new TextDecoder().decode(stdout);

      const lines = output.trim().split("\n").filter((l) => l.trim());
      for (const line of lines) {
        try {
          const data = JSON.parse(line);
          const name = data.Name;

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
   * Proactively look for running docker containers matching our services.
   * Uses the Docker API when available, falls back to CLI.
   */
  private async discoverRunningServices(): Promise<void> {
    // Try Docker API first
    if (this.dockerClient) {
      try {
        await this.discoverRunningServicesAPI();
        return;
      } catch {
        // Fall through to CLI
      }
    }

    // CLI fallback
    await this.discoverRunningServicesCLI();
  }

  /**
   * Discover running services using the Docker Engine API.
   * A single API call replaces multiple `docker compose ls` + `docker compose ps` calls.
   */
  private async discoverRunningServicesAPI(): Promise<void> {
    const containers = await this.dockerClient!.listContainers({
      status: ["running", "restarting"],
    });
    const foundServices = new Set<string>();

    for (const container of containers) {
      const serviceName = this.resolveServiceName(container);
      foundServices.add(serviceName);

      if (!this.services.has(serviceName)) {
        this.services.set(serviceName, {
          name: serviceName,
          label: serviceName.toUpperCase(),
          url: "",
          port: 0,
          status: "stopped",
        });
      }

      const isRunning = container.State === "running";
      this.updateStatus(serviceName, isRunning ? "running" : "starting");
    }

    for (const name of this.services.keys()) {
      if (!foundServices.has(name)) {
        this.updateStatus(name, "stopped");
      }
    }
  }

  /**
   * CLI-based service discovery (original implementation).
   */
  private async discoverRunningServicesCLI(): Promise<void> {
    const projectDir = getDashboardPaths().dockerLocalNetworkDir;
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

        const containers = psOutput.trim().split("\n").filter((l) => l.trim())
          .map((line) => {
            try {
              return JSON.parse(line);
            } catch {
              return null;
            }
          }).filter((c) => c !== null);

        for (const container of containers) {
          const serviceName = container.Service;
          const mappedName = serviceName.replace("local-", "");
          foundServices.add(mappedName);

          if (!this.services.has(mappedName)) {
            this.services.set(mappedName, {
              name: mappedName,
              label: mappedName.toUpperCase(),
              url: "",
              port: 0,
              status: "stopped",
            });
          }

          if (container.State === "running" || container.State === "starting") {
            this.updateStatus(
              mappedName,
              container.State === "running" ? "running" : "starting",
            );
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
      } catch {
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
        pds: 2583,
        plc: 2582,
        relay: 2584,
        appview: 3200,
        chat: 2585,
        pds2: 2587,
        video: 2586,
        ui: 2590,
      };
      if (ports[name]) baseUrl = `http://localhost:${ports[name]}`;
      else return null;
    }

    switch (name) {
      case "relay":
        return `${baseUrl}/api/relay/health`;
      case "pds":
      case "pds2":
        return `${baseUrl}/xrpc/com.atproto.server.describeServer`;
      case "appview":
        return `${baseUrl}/admin/backfill/status`;
      case "plc":
        return `${baseUrl}/_health`;
      default:
        return `${baseUrl}/_health`;
    }
  }

  getStatus(): Record<string, ServiceStatus> {
    return Object.fromEntries(this.services);
  }

  private updateStatus(name: string, status: ServiceStatusType) {
    const s = this.services.get(name);
    if (s && s.status !== status) {
      this.services.set(name, {
        ...s,
        status,
        healthy: status === "running" ? s.healthy : false,
      });
    }
  }

  private startHealthChecks() {
    if (this.healthInterval) return;
    this.healthInterval = setInterval(() => this.healthCheck(), 10000);
    this.healthCheck().catch(() => {});
  }

  // -----------------------------------------------------------------------
  // Docker API helpers
  // -----------------------------------------------------------------------

  /**
   * Resolve a human-readable service name from a container summary.
   * Uses compose labels first, then falls back to container name patterns.
   */
  private resolveServiceName(container: ContainerSummary): string {
    // Try compose service label first
    const composeService = composeServiceName(container);
    if (composeService) {
      return composeService.replace(/^local-/, "");
    }

    // Fall back to container name patterns
    for (const name of container.Names) {
      const clean = name.replace(/^\//, "");
      // Pattern: garazyk-e2e-<timestamp>-<service>-1
      const match = clean.match(/-(.+)-\d+$/);
      if (match) return match[1];
      // Pattern: local-<service>
      if (clean.startsWith("local-")) return clean.replace("local-", "");
    }

    return container.Names[0]?.replace(/^\//, "") ||
      container.Id.substring(0, 12);
  }

  /**
   * Stream container logs via the Docker Engine API.
   */
  private streamLogsViaAPI(
    containerId: string,
  ): Promise<AsyncIterable<string>> {
    const client = this.dockerClient!;
    const abort = new AbortController();

    async function* generate() {
      // Use the logs API with follow mode
      try {
        const resp = await fetch(
          `http://localhost/v1.43/containers/${containerId}/logs?follow=true&stdout=true&stderr=true&tail=100`,
          {
            client: (client as unknown as { _client: Deno.HttpClient })._client,
            signal: abort.signal,
          },
        );
        if (resp.body) {
          const reader = resp.body.getReader();
          const decoder = new TextDecoder();
          try {
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              yield decoder.decode(value, { stream: true });
            }
          } finally {
            reader.releaseLock();
          }
        }
      } catch {
        // Stream ended or was cancelled
      }
    }

    return Promise.resolve(generate());
  }

  /**
   * Stream container logs via the Docker CLI (fallback).
   */
  private streamLogsViaCLI(
    service: string,
  ): Promise<AsyncIterable<string>> {
    const projectDir = getDashboardPaths().dockerLocalNetworkDir;

    const command = new Deno.Command("docker", {
      args: [
        "compose",
        "-f",
        `${projectDir}/docker-compose.yml`,
        "logs",
        "-f",
        "--no-log-prefix",
        service,
      ],
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

    return Promise.resolve(generate());
  }

  /**
   * Handle real-time events from the ContainerEventWatcher.
   * Updates service status immediately instead of waiting for the next poll.
   */
  private handleWatcherEvent(event: WatcherEvent): void {
    const { serviceName } = event;

    switch (event.kind) {
      case "started":
        if (!this.services.has(serviceName)) {
          this.services.set(serviceName, {
            name: serviceName,
            label: serviceName.toUpperCase(),
            url: "",
            port: 0,
            status: "starting",
          });
        }
        this.updateStatus(serviceName, "running");
        break;
      case "healthy":
        this.updateStatus(serviceName, "running");
        break;
      case "unhealthy":
        this.updateStatus(serviceName, "error");
        break;
      case "died":
      case "oom":
        this.updateStatus(serviceName, "stopped");
        break;
    }
  }

  /**
   * Clean up Docker API resources.
   */
  destroy(): void {
    if (this.eventUnsubscribe) {
      this.eventUnsubscribe();
      this.eventUnsubscribe = null;
    }
    if (this.eventWatcher) {
      this.eventWatcher.close();
      this.eventWatcher = null;
    }
    if (this.dockerClient) {
      this.dockerClient.close();
      this.dockerClient = null;
    }
    if (this.healthInterval) {
      clearInterval(this.healthInterval);
      this.healthInterval = undefined;
    }
  }
}

/** Singleton network manager instance. */
export const networkManager: NetworkManagerApi = new NetworkManager();

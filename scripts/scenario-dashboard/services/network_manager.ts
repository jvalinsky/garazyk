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

import { fromFileUrl, join } from "$std/path/mod.ts";
import { ServiceStatus, ServiceStatusType } from "./types.ts";
import type { Run } from "./types.ts";
import { runManager } from "./run_manager.ts";
import { getTopologyServiceUrls } from "./topology_service.ts";
import {
  composeServiceName,
  ContainerEventWatcher,
  type ContainerSummary,
  cpuPercent,
  createDockerClient,
  DockerApiClient,
  formatMemory,
  healthStatus,
  type WatcherEvent,
} from "@garazyk/laweta";
import {
  startLocalNetwork,
  stopLocalNetwork,
} from "@garazyk/hamownia/atproto_network.ts";
import {
  loadRunResourceManifest,
  serviceUrlsFromResourceManifest,
} from "@garazyk/schemat";

const HOST_SERVICE_ROLES = [
  "plc",
  "pds",
  "pds2",
  "relay",
  "appview",
  "chat",
  "video",
  "germ",
  "mikrus",
  "beskid",
];

function isDenoTestRun(): boolean {
  return Deno.mainModule.endsWith("_test.ts") ||
    Deno.mainModule.endsWith(".test.ts");
}

/** Manages Docker service lifecycle, health checks, container stats, and log streaming. */
class NetworkManager {
  private services: Map<string, ServiceStatus> = new Map();
  private healthInterval?: number;
  private dockerClient: DockerApiClient | null = null;
  private eventWatcher: ContainerEventWatcher | null = null;
  private eventUnsubscribe: (() => void) | null = null;

  constructor() {
    // Start background health checking for the web server, but not during
    // Fresh builds or Deno tests where intervals and Docker event streams
    // leak across test cases.
    if (!Deno.args.includes("build") && !isDenoTestRun()) {
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

  async startAll(
    opts?: { pds2?: boolean; useBinary?: boolean },
  ): Promise<void> {
    try {
      await startLocalNetwork({
        withPds2: opts?.pds2,
        useBinary: opts?.useBinary,
        keepRunning: true,
      });

      await this.healthCheck();
    } catch (e) {
      console.error("[network] startAll failed:", e);
      throw e;
    }
  }

  async stopAll(opts?: { useBinary?: boolean }): Promise<void> {
    try {
      await stopLocalNetwork({
        useBinary: opts?.useBinary,
        keepRunning: false,
      });
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
   * When no Docker containers are found, falls back to probing binary
   * service URLs via HTTP.
   */
  private async discoverRunningServices(): Promise<void> {
    let dockerFound = false;

    // Try Docker API first
    if (this.dockerClient) {
      try {
        await this.discoverRunningServicesAPI();
        dockerFound = this.services.size > 0 &&
          [...this.services.values()].some((s) => s.status !== "stopped");
      } catch {
        // Fall through to CLI
      }
    }

    if (!dockerFound) {
      // CLI fallback
      await this.discoverRunningServicesCLI();
      dockerFound = this.services.size > 0 &&
        [...this.services.values()].some((s) => s.status !== "stopped");
    }

    // When no Docker containers are found, fall back to binary/host services.
    // The healthCheck() method will probe these URLs via HTTP to determine
    // actual running status.
    if (!dockerFound) {
      this.seedBinaryServiceDefaults();
    }
  }

  /**
   * Populate the services map with default binary service entries.
   * Actual running status is determined by subsequent HTTP health probes.
   * Uses the resource manifest when available, otherwise falls back to
   * default service URLs from the topology.
   */
  private seedBinaryServiceDefaults(): void {
    // In binary mode, only host services exist — clear stale Docker entries.
    // Safe because the dockerFound gate guarantees no running Docker containers.
    this.services.clear();

    const activeRun = runManager.getActiveRun();
    const status: ServiceStatusType = activeRun &&
        (activeRun.status === "starting" || activeRun.status === "running" ||
          activeRun.status === "stopping")
      ? "starting"
      : "stopped";
    const urls = this.resolveServiceUrls();
    const roles = new Set([...HOST_SERVICE_ROLES, ...Object.keys(urls)]);
    if (!activeRun?.pds2) roles.delete("pds2");

    for (const role of roles) {
      const url = urls[role] ?? "";
      if (!url) continue;
      this.services.set(role, {
        name: role,
        label: role.toUpperCase(),
        url,
        port: 0,
        status,
      });
    }
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
          url: this.resolveTopologyServiceUrl(serviceName),
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
          let mappedName = this.normalizeServiceRole(serviceName);
          foundServices.add(mappedName);

          if (!this.services.has(mappedName)) {
            this.services.set(mappedName, {
              name: mappedName,
              label: mappedName.toUpperCase(),
              url: this.resolveTopologyServiceUrl(mappedName),
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

  private resolveTopologyServiceUrl(name: string): string {
    const roleName = this.normalizeServiceRole(name);
    const serviceUrls = this.resolveServiceUrls();
    return serviceUrls[roleName] ?? "";
  }

  private resolveServiceUrls(): Record<string, string> {
    const activeRun = runManager.getActiveRun();
    const topologyName = activeRun?.topology ??
      Deno.env.get("ATPROTO_TOPOLOGY") ?? undefined;
    const topologyUrls = getTopologyServiceUrls(
      topologyName,
      activeRun?.pds2 === true,
    );
    return {
      ...topologyUrls,
      ...this.resolveManifestServiceUrls(activeRun),
    };
  }

  private resolveManifestServiceUrls(
    activeRun: Run | undefined,
  ): Record<string, string> {
    const manifestPath = activeRun?.manifestPath ??
      (activeRun?.runDir
        ? join(activeRun.runDir, "resource-manifest.json")
        : undefined);
    if (!manifestPath) return {};

    try {
      return serviceUrlsFromResourceManifest(
        loadRunResourceManifest(manifestPath),
      );
    } catch (e) {
      console.warn(
        `[network] failed to load resource manifest ${manifestPath}:`,
        e,
      );
      return {};
    }
  }

  private normalizeServiceRole(name: string): string {
    return name.replace(/^local-/, "");
  }

  async healthCheck(): Promise<Record<string, ServiceStatus>> {
    if (this.services.size === 0) {
      this.seedBinaryServiceDefaults();
    }

    const results: Record<string, ServiceStatus> = {};

    // If we have an active run, we should have a manifest with health probes
    // TODO: Load manifest from activeRun.manifestPath if available

    const checks = [...this.services].map(async ([name, s]) => {
      if (s.status === "stopped") {
        return [name, s] as const;
      }

      try {
        // Fallback to heuristic-based health checks if no manifest probes
        const healthUrl = this.getHealthUrl(name, s.url);
        if (!healthUrl) {
          return [name, s] as const;
        }

        const controller = new AbortController();
        const id = setTimeout(() => controller.abort(), 3000);
        const headers: Record<string, string> = {};
        if (name === "appview") {
          headers.Authorization = "Bearer localdevadmin";
        }
        const resp = await fetch(healthUrl, {
          signal: controller.signal,
          headers,
        }).finally(() => clearTimeout(id));

        const healthy = resp.ok;
        if (healthy && (s.status === "error" || s.status === "starting")) {
          this.updateStatus(name, "running");
        }

        const current = this.services.get(name) || s;
        const updated = { ...current, healthy };
        this.services.set(name, updated);
        return [name, updated] as const;
      } catch (e) {
        const current = this.services.get(name) || s;
        const updated = { ...current, healthy: false };
        this.services.set(name, updated);
        return [name, updated] as const;
      }
    });

    for (const [name, service] of await Promise.all(checks)) {
      results[name] = service;
    }

    return results;
  }

  private getHealthUrl(name: string, baseUrl: string): string | null {
    if (!baseUrl) {
      baseUrl = this.resolveTopologyServiceUrl(name);
      if (!baseUrl) return null;
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
    if (this.services.size === 0) {
      this.seedBinaryServiceDefaults();
    }
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
  private async streamLogsViaAPI(
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
            client: (client as any)._client,
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

    return generate();
  }

  /**
   * Stream container logs via the Docker CLI (fallback).
   */
  private async streamLogsViaCLI(
    service: string,
  ): Promise<AsyncIterable<string>> {
    const projectDir = join(
      fromFileUrl(new URL("../../../docker/local-network", import.meta.url)),
    );

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

    return generate();
  }

  /**
   * Handle real-time events from the ContainerEventWatcher.
   * Updates service status immediately instead of waiting for the next poll.
   */
  private handleWatcherEvent(event: WatcherEvent): void {
    const serviceName = this.normalizeServiceRole(event.serviceName);

    switch (event.kind) {
      case "started":
        if (!this.services.has(serviceName)) {
          this.services.set(serviceName, {
            name: serviceName,
            label: serviceName.toUpperCase(),
            url: this.resolveTopologyServiceUrl(serviceName),
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
export const networkManager = new NetworkManager();

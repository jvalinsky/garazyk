/**
 * Event-driven container monitoring for the Docker test harness.
 *
 * Uses the Docker Engine API /events stream to watch for container
 * lifecycle events (start, die, health_status, OOM) in real-time,
 * replacing polling-based health checks with near-instant notification.
 *
 * Architecture: the protocol logic (event interpretation, state
 * tracking) is separated from the I/O layer (Docker event stream)
 * using a sans-IO pattern. DockerEventParser is a pure synchronous
 * class that can be tested without a Docker daemon; the I/O shell
 * in ContainerEventWatcher feeds parsed events to the parser and
 * dispatches the resulting WatcherEvents.
 *
 * When OpenTelemetry is enabled, container lifecycle events and
 * health-check waits are traced as spans for observability.
 *
 * @module docker_events
 */

import {
  composeServiceName,
  type ContainerSummary,
  createDockerClient,
  type DockerApiClient,
  type DockerEvent,
  healthStatus,
} from "./docker_api.ts";
import { addSpanEvent, withSpan } from "@garazyk/scenario-runner";

// ---------------------------------------------------------------------------
// Scoped AbortError suppression
// ---------------------------------------------------------------------------

// Deno's unhandled rejection tracker fires before the microtask queue
// processes .catch() handlers on reader.read() promises. When
// abortController.abort() interrupts a pending reader.read() on the
// Docker event stream (the only way to break out of a Unix socket
// read in Deno), the AbortError is reported as unhandled even though
// the .catch() in streamEvents() handles it.
//
// We install a suppression handler scoped to the ContainerEventWatcher
// lifecycle — it's added in the constructor and removed in close().
// This avoids masking real AbortError bugs elsewhere in the process.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Event emitted when a container exits. */
export interface ContainerCrashEvent {
  /** Docker Compose service name. */
  serviceName: string;
  /** Docker container ID. */
  containerId: string;
  /** Container exit code. */
  exitCode: number;
  /** Whether the container was killed by the OOM killer. */
  oomKilled: boolean;
  /** Event timestamp in milliseconds since epoch. */
  timestamp: number;
}

/** Event emitted when a container health status changes. */
export interface ContainerHealthEvent {
  /** Docker Compose service name. */
  serviceName: string;
  /** Docker container ID. */
  containerId: string;
  /** Container health status. */
  status: string; // "healthy" | "unhealthy" | "starting"
  /** Event timestamp in milliseconds since epoch. */
  timestamp: number;
}

/** Parsed container event emitted by the watcher. */
export type WatcherEvent =
  | { kind: "started"; serviceName: string; containerId: string; timestamp: number }
  | { kind: "healthy"; serviceName: string; containerId: string; timestamp: number }
  | { kind: "unhealthy"; serviceName: string; containerId: string; timestamp: number }
  | {
    kind: "died";
    serviceName: string;
    containerId: string;
    exitCode: number;
    oomKilled: boolean;
    timestamp: number;
  }
  | { kind: "oom"; serviceName: string; containerId: string; timestamp: number };

/** Tracked state for a single container. */
interface ContainerState {
  status: string;
  exitCode: number;
  oomKilled: boolean;
}

interface Waiter {
  resolve: (value: boolean) => void;
  reject: (reason: Error) => void;
  timeoutId: number;
  serviceName: string;
  waitFor: "healthy" | "running";
}

// ---------------------------------------------------------------------------
// DockerEventParser (sans-IO core)
// ---------------------------------------------------------------------------

/**
 * Pure synchronous Docker event interpreter and container state tracker.
 *
 * Accepts parsed Docker events via feed(), updates internal state, and
 * returns WatcherEvent objects. No I/O, no async, no promises — fully
 * testable without a Docker daemon.
 *
 * The I/O boundary is at DockerApiClient.streamEvents(), which parses
 * JSON lines from the Docker socket. This class handles the protocol
 * logic of interpreting those events and tracking container state.
 */
export class DockerEventParser {
  private serviceNameToId: Map<string, string> = new Map();
  private idToServiceName: Map<string, string> = new Map();
  private containerStates: Map<string, ContainerState> = new Map();

  /**
   * Feed a parsed Docker event and return zero or more WatcherEvents.
   *
   * Updates the internal name→ID mapping and container state based
   * on the event action.
   */
  feed(event: DockerEvent): WatcherEvent[] {
    const containerId = event.actor?.ID || event.id || "";
    if (!containerId) return [];

    // Update name mapping from actor attributes
    const name = event.actor?.Attributes?.name ||
      event.actor?.Attributes?.["com.docker.compose.service"] || "";
    if (name) {
      this.serviceNameToId.set(name, containerId);
      this.idToServiceName.set(containerId, name);
    }

    const serviceName = this.idToServiceName.get(containerId) || name ||
      containerId.substring(0, 12);
    const timestamp = event.timeNano ? event.timeNano / 1_000_000 : event.time * 1000;

    const action = event.action || event.status || "";
    const results: WatcherEvent[] = [];

    if (
      action === "health_status" ||
      action === "health_status: healthy" ||
      action === "health_status: unhealthy"
    ) {
      const healthAttr = event.actor?.Attributes?.healthStatus || "";
      let status: string;
      if (action === "health_status: healthy" || healthAttr === "healthy") {
        status = "healthy";
      } else if (action === "health_status: unhealthy" || healthAttr === "unhealthy") {
        status = "unhealthy";
      } else {
        status = "unknown";
      }

      this.containerStates.set(containerId, { status, exitCode: 0, oomKilled: false });

      if (status === "healthy") {
        results.push({ kind: "healthy", serviceName, containerId, timestamp });
      } else if (status === "unhealthy") {
        results.push({ kind: "unhealthy", serviceName, containerId, timestamp });
      }
    } else if (action === "start") {
      this.containerStates.set(containerId, { status: "running", exitCode: 0, oomKilled: false });
      results.push({ kind: "started", serviceName, containerId, timestamp });
    } else if (action === "die") {
      const exitCode = parseInt(event.actor?.Attributes?.exitCode || "0", 10);
      const oomKilled = event.actor?.Attributes?.oomKill === "true" || false;
      this.containerStates.set(containerId, { status: "exited", exitCode, oomKilled });
      results.push({ kind: "died", serviceName, containerId, exitCode, oomKilled, timestamp });
    } else if (action === "oom") {
      this.containerStates.set(containerId, { status: "oom", exitCode: 137, oomKilled: true });
      results.push({ kind: "oom", serviceName, containerId, timestamp });
    }

    return results;
  }

  /**
   * Build the name→ID mapping from a list of containers.
   *
   * Call this at startup to populate the parser with known containers
   * before the event stream begins.
   */
  loadContainers(containers: ContainerSummary[]): void {
    for (const container of containers) {
      this.loadContainer(container);
    }
  }

  /**
   * Load a single container into the name→ID mapping.
   */
  loadContainer(container: ContainerSummary): void {
    const name = composeServiceName(container);
    if (name) {
      this.serviceNameToId.set(name, container.Id);
      this.idToServiceName.set(container.Id, name);
    }
    // Also index by container name (strip leading /)
    for (const n of container.Names) {
      const clean = n.replace(/^\//, "");
      this.serviceNameToId.set(clean, container.Id);
      this.idToServiceName.set(container.Id, clean);
    }
  }

  /** Look up a container ID by service name. */
  getContainerId(serviceName: string): string | undefined {
    return this.serviceNameToId.get(serviceName);
  }

  /** Look up the tracked state for a container. */
  getContainerState(containerId: string): ContainerState | undefined {
    return this.containerStates.get(containerId);
  }

  /** Check if a service is known to be healthy. */
  isHealthy(serviceName: string): boolean {
    const id = this.serviceNameToId.get(serviceName);
    if (!id) return false;
    return this.containerStates.get(id)?.status === "healthy";
  }

  /** Check if a service is known to be running. */
  isRunning(serviceName: string): boolean {
    const id = this.serviceNameToId.get(serviceName);
    if (!id) return false;
    return this.containerStates.get(id)?.status === "running";
  }

  /** Check if a service is known to have exited (died or OOM). */
  isExited(serviceName: string): boolean {
    const id = this.serviceNameToId.get(serviceName);
    if (!id) return false;
    const state = this.containerStates.get(id);
    if (!state) return false;
    return state.status === "exited" || state.status === "oom" || state.oomKilled;
  }
}

// ---------------------------------------------------------------------------
// Container Event Watcher
// ---------------------------------------------------------------------------

/**
 * Watches Docker container events and provides promise-based waiting
 * for container health and lifecycle states.
 *
 * Usage:
 * ```typescript
 * const watcher = await ContainerEventWatcher.create();
 * const healthy = await watcher.waitForHealthy("local-pds", 60_000);
 * await watcher.close();
 * ```
 */
export class ContainerEventWatcher {
  private client: DockerApiClient;
  private parser: DockerEventParser = new DockerEventParser();
  private eventStream: AsyncIterable<DockerEvent> | null = null;
  private abortController: AbortController = new AbortController();
  private waiters: Waiter[] = [];
  private subscribers: Array<(event: WatcherEvent) => void> = [];
  private _closed = false;
  private eventLoopPromise: Promise<void> | null = null;
  private constructor(client: DockerApiClient) {
    this.client = client;
  }

  /**
   * Create and start a ContainerEventWatcher.
   *
   * Returns null if the Docker API is not available.
   */
  static async create(socketPath?: string): Promise<ContainerEventWatcher | null> {
    const client = await createDockerClient(socketPath);
    if (!client) return null;

    const watcher = new ContainerEventWatcher(client);
    await watcher.start();
    return watcher;
  }

  /** Whether the watcher is active and receiving events. */
  get active(): boolean {
    return !this._closed && this.eventLoopPromise !== null;
  }

  // -----------------------------------------------------------------------
  // Waiting
  // -----------------------------------------------------------------------

  /**
   * Wait for a container to become healthy.
   *
   * Resolves true if the container becomes healthy within the timeout.
   * Resolves false if the container dies, becomes unhealthy, or the
   * timeout expires.
   */
  waitForHealthy(serviceName: string, timeoutMs: number): Promise<boolean> {
    return withSpan(
      "docker.waitForHealthy",
      async () => await this.waitFor(serviceName, "healthy", timeoutMs),
      { "docker.service_name": serviceName, "docker.timeout_ms": timeoutMs },
    );
  }

  /**
   * Wait for a container to reach "running" state.
   *
   * Resolves true if the container starts within the timeout.
   * Resolves false if the container dies or the timeout expires.
   */
  waitForRunning(serviceName: string, timeoutMs: number): Promise<boolean> {
    return withSpan(
      "docker.waitForRunning",
      async () => await this.waitFor(serviceName, "running", timeoutMs),
      { "docker.service_name": serviceName, "docker.timeout_ms": timeoutMs },
    );
  }

  /**
   * Subscribe to watcher events for all monitored containers.
   *
   * Returns a function that unsubscribes when called.
   */
  subscribe(callback: (event: WatcherEvent) => void): () => void {
    this.subscribers.push(callback);
    return () => {
      const index = this.subscribers.indexOf(callback);
      if (index >= 0) this.subscribers.splice(index, 1);
    };
  }

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /** Stop watching and release resources. */
  async close(): Promise<void> {
    if (this._closed) return;
    this._closed = true;

    // Abort the event stream.
    if (!this.abortController.signal.aborted) {
      this.abortController.abort();
    }

    // Reject all pending waiters
    for (const waiter of this.waiters) {
      clearTimeout(waiter.timeoutId);
      waiter.reject(new Error("ContainerEventWatcher closed"));
    }
    this.waiters = [];

    // Wait briefly for the event loop promise to settle.
    // reader.read() on a Unix socket HTTP response blocks the Deno
    // event loop, so abort() may not propagate immediately. A short
    // timeout avoids hanging if the abort signal doesn't reach the
    // Rust HTTP client layer in time.
    if (this.eventLoopPromise) {
      await Promise.race([
        this.eventLoopPromise.catch(() => {}),
        new Promise<void>((resolve) => setTimeout(resolve, 100)),
      ]);
      this.eventLoopPromise = null;
    }

    this.client.close();
  }

  // -----------------------------------------------------------------------
  // Internal
  // -----------------------------------------------------------------------

  private async start(): Promise<void> {
    // Build initial container name → ID mapping
    await this.buildContainerMap();

    // Start the event stream
    this.eventStream = this.client.streamEvents(
      {
        type: ["container"],
        event: ["start", "die", "health_status", "oom"],
      },
      this.abortController.signal,
    );

    // Process events in the background.
    this.eventLoopPromise = this.processEvents();
  }

  private async buildContainerMap(): Promise<void> {
    try {
      const containers = await this.client.listContainers();
      this.parser.loadContainers(containers);
    } catch {
      // Container listing may fail if daemon is busy — events will
      // still work for containers that appear after we start watching
    }
  }

  private async processEvents(): Promise<void> {
    if (!this.eventStream) return;

    try {
      for await (const event of this.eventStream) {
        if (this._closed) break;
        const watcherEvents = this.parser.feed(event);
        for (const watcherEvent of watcherEvents) {
          this.emit(watcherEvent);
          this.resolveWaiters(watcherEvent);
          // Record OTel span events for died/oom
          if (watcherEvent.kind === "died") {
            addSpanEvent("container.died", {
              "container.service": watcherEvent.serviceName,
              "container.exit_code": watcherEvent.exitCode,
              "container.oom_killed": watcherEvent.oomKilled,
            }).catch(() => {});
          } else if (watcherEvent.kind === "oom") {
            addSpanEvent("container.oom", {
              "container.service": watcherEvent.serviceName,
            }).catch(() => {});
          }
        }
      }
    } catch (err) {
      if (!this._closed && !(err && err.name === "AbortError")) {
        console.error("[docker_events] event stream error:", err);
      }
    }
  }

  private emit(event: WatcherEvent): void {
    for (const subscriber of this.subscribers) {
      try {
        subscriber(event);
      } catch {
        // Subscriber errors shouldn't break the event loop
      }
    }
  }

  private resolveWaiters(event: WatcherEvent): void {
    const { serviceName, kind } = event;

    if (kind === "healthy") {
      this.resolveWaitersFor(serviceName, "healthy", true);
    } else if (kind === "unhealthy") {
      this.resolveWaitersFor(serviceName, "healthy", false);
    } else if (kind === "started") {
      this.resolveWaitersFor(serviceName, "running", true);
    } else if (kind === "died" || kind === "oom") {
      this.resolveWaitersFor(serviceName, "running", false);
      this.resolveWaitersFor(serviceName, "healthy", false);
    }
  }

  private resolveWaitersFor(
    serviceName: string,
    waitFor: "healthy" | "running",
    result: boolean,
  ): void {
    const matching = this.waiters.filter(
      (w) => w.serviceName === serviceName && w.waitFor === waitFor,
    );
    for (const waiter of matching) {
      clearTimeout(waiter.timeoutId);
      waiter.resolve(result);
    }
    this.waiters = this.waiters.filter(
      (w) => !(w.serviceName === serviceName && w.waitFor === waitFor),
    );
  }

  private waitFor(
    serviceName: string,
    waitFor: "healthy" | "running",
    timeoutMs: number,
  ): Promise<boolean> {
    if (this._closed) {
      return Promise.reject(new Error("ContainerEventWatcher is closed"));
    }

    // Check if the container is already in the desired state
    const containerId = this.parser.getContainerId(serviceName);
    if (containerId) {
      const state = this.parser.getContainerState(containerId);
      if (state) {
        if (waitFor === "healthy" && state.status === "healthy") return Promise.resolve(true);
        if (waitFor === "running" && state.status === "running") return Promise.resolve(true);
        if (state.status === "exited" || state.status === "dead" || state.oomKilled) {
          return Promise.resolve(false);
        }
      }
    }

    // Also check via inspect for current state (handles the case where
    // the container became healthy before we started watching)
    if (containerId) {
      return this.waitForViaInspectOrEvents(serviceName, containerId, waitFor, timeoutMs);
    }

    // No known container ID — wait for events, but also periodically
    // try to discover the container via listContainers so we can inspect
    // it directly (which is more reliable than waiting for events).
    return new Promise<boolean>((resolve, reject) => {
      let settled = false;

      const settle = (result: boolean) => {
        if (settled) return;
        settled = true;
        clearInterval(discoveryIntervalId);
        clearTimeout(timeoutId);
        this.waiters = this.waiters.filter((w) => w !== waiter);
        resolve(result);
      };

      const timeoutId = setTimeout(() => {
        settle(false);
      }, timeoutMs);

      const waiter: Waiter = {
        resolve: settle,
        reject: (err: Error) => {
          if (settled) return;
          settled = true;
          clearInterval(discoveryIntervalId);
          clearTimeout(timeoutId);
          reject(err);
        },
        timeoutId,
        serviceName,
        waitFor,
      };
      this.waiters.push(waiter);

      // Periodically try to discover the container and inspect it.
      const discoveryIntervalId = setInterval(async () => {
        try {
          await this.buildContainerMap();
          const discoveredId = this.parser.getContainerId(serviceName);
          if (discoveredId) {
            const inspect = await this.client.inspectContainer(discoveredId);
            const status = healthStatus(inspect);

            if (waitFor === "healthy" && status === "healthy") {
              settle(true);
            } else if (waitFor === "running" && inspect.State.Running) {
              settle(true);
            } else if (
              inspect.State.Dead || (!inspect.State.Running && inspect.State.ExitCode !== 0)
            ) {
              settle(false);
            }
          }
        } catch {
          // Container may not exist yet — keep trying
        }
      }, 5000);
    });
  }

  /**
   * Check current container state via inspect, then fall back to
   * event-based waiting with periodic inspect polling.
   *
   * Docker's health_status events are unreliable — they may not fire
   * for all health transitions, or the event stream may miss them.
   * Polling inspect every 5 seconds ensures we detect health changes
   * even when events are lost.
   */
  private async waitForViaInspectOrEvents(
    serviceName: string,
    containerId: string,
    waitFor: "healthy" | "running",
    timeoutMs: number,
  ): Promise<boolean> {
    try {
      const inspect = await this.client.inspectContainer(containerId);
      const status = healthStatus(inspect);

      if (waitFor === "healthy" && status === "healthy") return true;
      if (waitFor === "running" && inspect.State.Running) return true;

      // If the container is already dead, no point waiting
      if (inspect.State.Dead || (!inspect.State.Running && inspect.State.ExitCode !== 0)) {
        return false;
      }
    } catch {
      // Inspect failed — fall through to event-based waiting
    }

    // Not yet in the desired state — register an event waiter AND
    // start a periodic inspect poll as a fallback.
    return new Promise<boolean>((resolve, reject) => {
      let settled = false;

      const settle = (result: boolean) => {
        if (settled) return;
        settled = true;
        clearInterval(pollIntervalId);
        clearTimeout(timeoutId);
        this.waiters = this.waiters.filter((w) => w !== waiter);
        resolve(result);
      };

      const timeoutId = setTimeout(() => {
        settle(false);
      }, timeoutMs);

      const waiter: Waiter = {
        resolve: settle,
        reject: (err: Error) => {
          if (settled) return;
          settled = true;
          clearInterval(pollIntervalId);
          clearTimeout(timeoutId);
          reject(err);
        },
        timeoutId,
        serviceName,
        waitFor,
      };
      this.waiters.push(waiter);

      // Periodic inspect poll — catches health transitions that
      // Docker's event stream misses or delivers late.
      const pollIntervalId = setInterval(async () => {
        try {
          const inspect = await this.client.inspectContainer(containerId);
          const status = healthStatus(inspect);

          if (waitFor === "healthy" && status === "healthy") {
            settle(true);
          } else if (waitFor === "running" && inspect.State.Running) {
            settle(true);
          } else if (
            inspect.State.Dead || (!inspect.State.Running && inspect.State.ExitCode !== 0)
          ) {
            settle(false);
          }
        } catch {
          // Inspect failed — keep polling
        }
      }, 5000);
    });
  }
}

// ---------------------------------------------------------------------------
// Convenience: one-shot health wait
// ---------------------------------------------------------------------------

/**
 * Wait for a Docker Compose service to become healthy using the
 * Docker Engine API /events stream.
 *
 * Falls back to CLI-based polling if the API is unavailable.
 *
 * @param serviceName - Docker Compose service name (e.g. "local-pds")
 * @param timeoutMs - Maximum time to wait in milliseconds
 * @returns true if the service became healthy, false if timed out or crashed
 */
export async function waitForServiceHealthy(
  serviceName: string,
  timeoutMs: number,
): Promise<boolean> {
  const watcher = await ContainerEventWatcher.create();
  if (!watcher) {
    // Fallback: use CLI-based polling
    return waitForServiceHealthyCLI(serviceName, timeoutMs);
  }

  try {
    return await watcher.waitForHealthy(serviceName, timeoutMs);
  } finally {
    await watcher.close();
  }
}

/**
 * CLI-based fallback for waiting for a service to become healthy.
 *
 * Polls `docker inspect` every 500ms.
 */
async function waitForServiceHealthyCLI(
  serviceName: string,
  timeoutMs: number,
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const proc = new Deno.Command("docker", {
        args: [
          "inspect",
          "--format",
          "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}",
          serviceName,
        ],
        stdout: "piped",
        stderr: "piped",
      });
      const { code, stdout } = await proc.output();
      if (code === 0) {
        const status = new TextDecoder().decode(stdout).trim();
        if (status === "healthy" || status === "running") return true;
        if (status === "unhealthy" || status === "exited" || status === "dead") return false;
      }
    } catch {
      // Container may not exist yet
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return false;
}

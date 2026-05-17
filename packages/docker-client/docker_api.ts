/**
 * Docker Engine API client over Unix socket.
 *
 * Uses Deno.createHttpClient with Unix socket proxy support to make
 * standard fetch() calls to the Docker daemon, eliminating subprocess
 * overhead from docker CLI invocations.
 *
 * Falls back to CLI-based operations when the socket is unavailable.
 *
 * When OpenTelemetry is enabled (OTEL_DENO=true), each API call is
 * wrapped in a span for observability in the test harness.
 *
 * @module docker_api
 */

import { formatBytes } from "@garazyk/scenario-runner";
import { withSpan } from "@garazyk/scenario-runner";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Docker Engine API version used for all requests. */
const API_VERSION = "v1.43";

/** Default Unix socket paths to probe (in order). */
const DEFAULT_SOCKET_PATHS = [
  `${Deno.env.get("HOME")}/.orbstack/run/docker.sock`, // OrbStack
  `${Deno.env.get("HOME")}/.docker/run/docker.sock`, // Docker Desktop
  "/var/run/docker.sock",
  "/run/docker.sock",
];

// ---------------------------------------------------------------------------
// Response types (subset of Docker Engine API)
// ---------------------------------------------------------------------------

/** Mirrors the Docker Engine API `/version` response. */
export interface DockerVersion {
  /** Docker API version reported by the daemon. */
  ApiVersion: string;
  /** CPU architecture reported by the daemon. */
  Arch: string;
  /** Daemon build time. */
  BuildTime: string;
  /** Component versions included in the daemon build. */
  Components: Array<{ Name: string; Version: string; Details?: Record<string, string> }>;
  /** Git commit used to build the daemon. */
  GitCommit: string;
  /** Go toolchain version used to build the daemon. */
  GoVersion: string;
  /** Minimum supported Docker API version. */
  MinAPIVersion: string;
  /** Operating system reported by the daemon. */
  Os: string;
  /** Platform metadata reported by the daemon. */
  Platform: { Name: string };
  /** Docker Engine version string. */
  Version: string;
}

/** Mirrors a `/containers/json` entry from the Docker Engine API. */
export interface ContainerSummary {
  /** Container ID. */
  Id: string;
  /** Container names, including the leading slash. */
  Names: string[];
  /** Image name or ID used by the container. */
  Image: string;
  /** Image ID used by the container. */
  ImageID: string;
  /** Command associated with the container. */
  Command: string;
  /** Creation timestamp in Unix seconds. */
  Created: number;
  /** Container state string. */
  State: string;
  /** Human-readable status string. */
  Status: string;
  /** Published and exposed port mappings. */
  Ports: Array<{
    IP?: string;
    PrivatePort: number;
    PublicPort?: number;
    Type: string;
  }>;
  /** Container labels. */
  Labels: Record<string, string>;
  /** Writable layer size in bytes. */
  SizeRw?: number;
  /** Root filesystem size in bytes. */
  SizeRootFs?: number;
  /** Host configuration details included in the summary response. */
  HostConfig: { NetworkMode: string };
  /** Network settings included in the summary response. */
  NetworkSettings: {
    Networks: Record<string, {
      NetworkID: string;
      EndpointID: string;
      Gateway: string;
      IPAddress: string;
      IPPrefixLen: number;
      MacAddress: string;
    }>;
  };
  /** Container mounts. */
  Mounts: Array<{
    Name?: string;
    Source: string;
    Destination: string;
    Driver?: string;
    Mode?: string;
    RW: boolean;
  }>;
}

/** Mirrors a `/containers/{id}/json` response from the Docker Engine API. */
export interface ContainerInspect {
  /** Container ID. */
  Id: string;
  /** Creation timestamp. */
  Created: string;
  /** Container name. */
  Name: string;
  /** Container runtime state. */
  State: {
    Status: string;
    Running: boolean;
    Paused: boolean;
    Restarting: boolean;
    OOMKilled: boolean;
    Dead: boolean;
    Pid: number;
    ExitCode: number;
    Error: string;
    StartedAt: string;
    FinishedAt: string;
    Health?: {
      Status: string;
      FailingStreak: number;
      Log: Array<{
        Start: string;
        End: string;
        ExitCode: number;
        Output: string;
      }>;
    };
  };
  /** Container configuration. */
  Config: {
    Image: string;
    Labels: Record<string, string>;
    Env: string[];
    Healthcheck?: {
      Test: string[];
      Interval: number;
      Timeout: number;
      Retries: number;
      StartPeriod: number;
    };
  };
  /** Container network settings. */
  NetworkSettings: {
    Bridge: string;
    Ports: Record<string, Array<{ HostIp: string; HostPort: string }> | null>;
    Networks: Record<string, {
      NetworkID: string;
      EndpointID: string;
      Gateway: string;
      IPAddress: string;
      IPPrefixLen: number;
      MacAddress: string;
    }>;
  };
  /** Container mounts. */
  Mounts: Array<{
    Type: string;
    Name?: string;
    Source: string;
    Destination: string;
    Driver?: string;
    Mode: string;
    RW: boolean;
  }>;
}

/** Mirrors a Docker Engine API event object. */
export interface DockerEvent {
  /** Event object type. */
  type: string;
  /** Event action. */
  action: string;
  /** Actor that emitted the event. */
  actor: {
    ID: string;
    Attributes: Record<string, string>;
  };
  /** Event scope. */
  scope: string;
  /** Event timestamp in Unix seconds. */
  time: number;
  /** Event timestamp in Unix nanoseconds. */
  timeNano: number;
  /** Legacy field present in some event types. */
  status?: string;
  /** Legacy field present in some event types. */
  id?: string;
  /** Legacy field present in some event types. */
  from?: string;
}

/** Mirrors a `/containers/{id}/stats` response from the Docker Engine API. */
export interface ContainerStats {
  /** Timestamp when the stats snapshot was read. */
  read: string;
  /** Timestamp of the previous stats snapshot. */
  preread: string;
  /** Number of processes in the container. */
  num_procs: number;
  /** Current CPU usage statistics. */
  cpu_stats: {
    cpu_usage: {
      total_usage: number;
      percpu_usage: number[];
      usage_in_kernelmode: number;
      usage_in_usermode: number;
    };
    system_cpu_usage: number;
    online_cpus: number;
    throttling_data: {
      periods: number;
      throttled_periods: number;
      throttled_time: number;
    };
  };
  /** Previous CPU usage statistics. */
  precpu_stats: ContainerStats["cpu_stats"];
  /** Current memory usage statistics. */
  memory_stats: {
    usage: number;
    max_usage: number;
    limit: number;
    stats: {
      cache: number;
      rss: number;
    };
    failcnt: number;
  };
  /** Block I/O statistics. */
  blkio_stats: {
    io_service_bytes_recursive: Array<{
      major: number;
      minor: number;
      op: string;
      value: number;
    }>;
  };
  /** Per-network traffic statistics. */
  networks: Record<string, {
    rx_bytes: number;
    rx_packets: number;
    rx_errors: number;
    rx_dropped: number;
    tx_bytes: number;
    tx_packets: number;
    tx_errors: number;
    tx_dropped: number;
  }>;
}

/** Options for the Docker Engine API `/containers/{id}/logs` endpoint. */
export interface ContainerLogsOptions {
  /** Include stdout output. */
  stdout?: boolean;
  /** Include stderr output. */
  stderr?: boolean;
  /** Keep the log stream open. */
  follow?: boolean;
  /** Number of trailing lines to return, or `all`. */
  tail?: string;
  /** Include timestamps in log output. */
  timestamps?: boolean;
}

// ---------------------------------------------------------------------------
// Docker API Client
// ---------------------------------------------------------------------------

/** Docker Engine API client over a Unix socket. */
export class DockerApiClient {
  private client: Deno.HttpClient | null = null;
  private _socketPath: string;
  private _available: boolean | null = null;
  private _baseUrl: string;
  private _useUnix = true;

  constructor(endpoint?: string) {
    const host = endpoint || Deno.env.get("DOCKER_HOST") || "";
    if (host.startsWith("tcp://") || host.startsWith("http://") || host.startsWith("https://")) {
      this._useUnix = false;
      this._socketPath = "";
      this._baseUrl = host.replace("tcp://", "http://");
      if (!this._baseUrl.includes("/v")) {
        this._baseUrl = this._baseUrl.replace(/\/$/, "") + `/${API_VERSION}`;
      }
    } else {
      this._socketPath = endpoint || detectSocketPath();
      this._baseUrl = `http://localhost/${API_VERSION}`;
    }
  }

  /** Whether the Docker socket is available and the daemon is responding. */
  get available(): boolean | null {
    return this._available;
  }

  /** The resolved socket path. */
  get socketPath(): string {
    return this._socketPath;
  }

  /** Initialize the client and check daemon availability. */
  async init(): Promise<boolean> {
    try {
      if (this._useUnix) {
        this.client = Deno.createHttpClient({
          proxy: {
            transport: "unix",
            path: this._socketPath,
          },
        });
      } else {
        this.client = Deno.createHttpClient({});
      }
      const ok = await this.ping();
      this._available = ok;
      return ok;
    } catch (e) {
      console.warn("[docker-api] failed to initialize Docker client", e);
      this._available = false;
      this.client = null;
      return false;
    }
  }

  /** Close the underlying HTTP client. */
  close(): void {
    if (this.client) {
      this.client.close();
      this.client = null;
    }
  }

  // -----------------------------------------------------------------------
  // System
  // -----------------------------------------------------------------------

  /** Ping the Docker daemon. Returns true if the daemon is alive. */
  async ping(): Promise<boolean> {
    try {
      const resp = await this.request("GET", "/_ping");
      // Consume the body to avoid resource leaks
      await resp.body?.cancel().catch(() => {});
      return resp.status === 200;
    } catch (e) {
      console.warn("[docker-api] ping failed", e);
      return false;
    }
  }

  /** Get Docker version information. */
  async version(): Promise<DockerVersion> {
    return await withSpan(
      "docker.version",
      () => this.requestJSON<DockerVersion>("GET", "/version"),
    );
  }

  // -----------------------------------------------------------------------
  // Containers
  // -----------------------------------------------------------------------

  /** List containers. */
  async listContainers(filters?: Record<string, string[]>): Promise<ContainerSummary[]> {
    const params = new URLSearchParams();
    if (filters) {
      params.set("filters", JSON.stringify(filters));
    }
    const path = `/containers/json${params.toString() ? "?" + params.toString() : ""}`;
    return await withSpan(
      "docker.listContainers",
      () => this.requestJSON<ContainerSummary[]>("GET", path),
      { "docker.filter_count": String(filters ? Object.keys(filters).length : 0) },
    );
  }

  /** Inspect a container. */
  async inspectContainer(id: string): Promise<ContainerInspect> {
    return await withSpan(
      "docker.inspectContainer",
      () => this.requestJSON<ContainerInspect>("GET", `/containers/${id}/json`),
      { "docker.container_id": id.substring(0, 12) },
    );
  }

  /** Get container logs. */
  async containerLogs(id: string, opts: ContainerLogsOptions = {}): Promise<string> {
    const params = new URLSearchParams();
    if (opts.stdout !== false) params.set("stdout", "true");
    if (opts.stderr !== false) params.set("stderr", "true");
    if (opts.follow) params.set("follow", "true");
    if (opts.tail) params.set("tail", opts.tail);
    if (opts.timestamps) params.set("timestamps", "true");
    return await withSpan("docker.containerLogs", async () => {
      const resp = await this.request("GET", `/containers/${id}/logs?${params.toString()}`);
      return await demuxLogStream(resp);
    }, { "docker.container_id": id.substring(0, 12) });
  }

  /** Get container stats (single snapshot). */
  async containerStats(id: string, opts?: { oneShot?: boolean }): Promise<ContainerStats> {
    const params = new URLSearchParams();
    params.set("stream", "false");
    if (opts?.oneShot) params.set("one-shot", "true");
    const qs = params.toString();
    return await withSpan("docker.containerStats", () =>
      this.requestJSON<ContainerStats>(
        "GET",
        `/containers/${id}/stats?${qs}`,
      ), { "docker.container_id": id.substring(0, 12) });
  }

  /**
   * Stream container stats as an async iterable.
   *
   * Yields `ContainerStats` objects continuously until the stream
   * is closed, the signal is aborted, or the caller breaks out.
   *
   * @param id - Container ID or name
   * @param signal - Optional AbortSignal to cancel the stream
   */
  async *streamContainerStats(
    id: string,
    signal?: AbortSignal,
  ): AsyncIterable<ContainerStats> {
    const resp = await this.request(
      "GET",
      `/containers/${id}/stats?stream=true`,
      undefined,
      signal,
    );

    if (!resp.body) return;

    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        if (signal?.aborted) break;
        const { done, value } = await reader.read().catch((err: Error) => {
          // AbortError is expected when close() cancels the stream.
          if (err.name === "AbortError") {
            return { done: true as const, value: undefined as unknown as Uint8Array };
          }
          throw err;
        });
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;
          try {
            yield JSON.parse(trimmed) as ContainerStats;
          } catch {
            // Skip malformed lines
          }
        }
      }
    } finally {
      reader.releaseLock();
      try {
        resp.body?.cancel().catch(() => {});
      } catch { /* ignore */ }
    }
  }

  /** Wait for a container to stop. Returns the exit code. */
  async waitContainer(id: string): Promise<{ StatusCode: number }> {
    return await withSpan(
      "docker.waitContainer",
      () => this.requestJSON<{ StatusCode: number }>("POST", `/containers/${id}/wait`),
      { "docker.container_id": id.substring(0, 12) },
    );
  }

  // -----------------------------------------------------------------------
  // Events (streaming)
  // -----------------------------------------------------------------------

  /**
   * Stream Docker events as an async iterable.
   *
   * The caller should consume events from the iterable and break out
   * of the loop when done. Calling `return()` on the generator or
   * breaking out of a `for await` loop will close the underlying
   * stream.
   *
   * @param filters - Event filters (e.g. `{ type: ["container"], event: ["health_status"] }`)
   * @param signal - Optional AbortSignal to cancel the stream
   */
  async *streamEvents(
    filters?: Record<string, string[]>,
    signal?: AbortSignal,
  ): AsyncIterable<DockerEvent> {
    const params = new URLSearchParams();
    if (filters) {
      params.set("filters", JSON.stringify(filters));
    }
    const path = `/events${params.toString() ? "?" + params.toString() : ""}`;
    const resp = await this.request("GET", path, undefined, signal);

    if (!resp.body) {
      return;
    }

    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        if (signal?.aborted) break;
        const { done, value } = await reader.read().catch((err: Error) => {
          // AbortError is expected when close() cancels the stream.
          if (err.name === "AbortError") {
            return { done: true as const, value: undefined as unknown as Uint8Array };
          }
          throw err;
        });
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        // Keep the last (possibly incomplete) line in the buffer
        buffer = lines.pop() || "";

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;
          try {
            yield JSON.parse(trimmed) as DockerEvent;
          } catch {
            // Skip malformed lines (Docker sometimes sends empty lines)
          }
        }
      }
    } finally {
      reader.releaseLock();
      try {
        resp.body?.cancel().catch(() => {});
      } catch { /* ignore */ }
    }
  }

  // -----------------------------------------------------------------------
  // Internal
  // -----------------------------------------------------------------------

  private async request(
    method: string,
    path: string,
    body?: unknown,
    signal?: AbortSignal,
  ): Promise<Response> {
    if (!this.client) {
      throw new Error("DockerApiClient not initialized. Call init() first.");
    }

    const url = `${this._baseUrl}${path}`;
    // `client` is a Deno-specific extension to RequestInit that enables
    // Unix socket proxy transport. It requires the --unstable-net flag
    // or Deno 2.x with full permissions (-A).
    const opts: RequestInit & { client?: Deno.HttpClient } = {
      method,
      client: this.client,
      signal,
    };

    if (body !== undefined) {
      opts.headers = { "Content-Type": "application/json" };
      opts.body = JSON.stringify(body);
    }

    const resp = await fetch(url, opts as RequestInit);
    if (!resp.ok && resp.status !== 101) {
      const text = await resp.text().catch(() => "");
      throw new DockerApiError(resp.status, path, text);
    }
    return resp;
  }

  private async requestJSON<T>(method: string, path: string): Promise<T> {
    const resp = await this.request(method, path);
    return await resp.json();
  }
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

/** Error thrown when a Docker Engine API request fails. */
export class DockerApiError extends Error {
  /**
   * Create a Docker API error.
   *
   * @param status - HTTP status returned by the Docker Engine API.
   * @param path - Request path that failed.
   * @param body - Response body returned by the Docker Engine API.
   */
  constructor(
    /** HTTP status returned by the Docker Engine API. */
    public readonly status: number,
    /** Request path that failed. */
    public readonly path: string,
    /** Response body returned by the Docker Engine API. */
    public readonly body: string,
  ) {
    super(`Docker API ${status} on ${path}: ${body.substring(0, 200)}`);
    this.name = "DockerApiError";
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Detect the Docker socket path from environment or common locations. */
function detectSocketPath(): string {
  // Check DOCKER_HOST first (supports unix:// and tcp://)
  const dockerHost = Deno.env.get("DOCKER_HOST");
  if (dockerHost) {
    const match = dockerHost.match(/^unix:\/\/(.+)$/);
    if (match) return match[1];
    // tcp:// host — we can't use Unix socket, fall through
  }

  // Probe common paths
  for (const path of DEFAULT_SOCKET_PATHS) {
    try {
      const stat = Deno.statSync(path);
      // Sockets may report as isFile: false, so we check existence
      if (stat) return path;
    } catch {
      // Path doesn't exist, try next
    }
  }

  // Default to standard path even if it doesn't exist yet
  return "/var/run/docker.sock";
}

/**
 * Create and initialize a DockerApiClient.
 *
 * Returns null if the Docker daemon is not available.
 */
export async function createDockerClient(socketPath?: string): Promise<DockerApiClient | null> {
  const client = new DockerApiClient(socketPath);
  const available = await client.init();
  if (!available) {
    client.close();
    return null;
  }
  return client;
}

/**
 * Find a container's compose service name from its labels.
 *
 * Docker Compose sets `com.docker.compose.service` on each container.
 */
export function composeServiceName(container: ContainerSummary | ContainerInspect): string | null {
  const labels = "Config" in container ? container.Config.Labels : container.Labels;
  return labels?.["com.docker.compose.service"] || null;
}

/**
 * Find a container's compose project name from its labels.
 */
export function composeProjectName(container: ContainerSummary | ContainerInspect): string | null {
  const labels = "Config" in container ? container.Config.Labels : container.Labels;
  return labels?.["com.docker.compose.project"] || null;
}

/**
 * Get the health status from a container inspect result.
 *
 * Returns "healthy", "unhealthy", "starting", or the raw container state
 * if no health check is defined.
 */
export function healthStatus(container: ContainerInspect): string {
  if (container.State.Health) {
    return container.State.Health.Status; // "starting", "healthy", "unhealthy"
  }
  return container.State.Status; // "running", "exited", etc.
}

/**
 * Compute CPU percentage from a container stats snapshot.
 *
 * Returns a number like 1.23 meaning 1.23% CPU usage.
 */
export function cpuPercent(stats: ContainerStats): number {
  const cpuDelta = stats.cpu_stats.cpu_usage.total_usage -
    stats.precpu_stats.cpu_usage.total_usage;
  const systemDelta = stats.cpu_stats.system_cpu_usage -
    stats.precpu_stats.system_cpu_usage;
  const cpuCount = stats.cpu_stats.online_cpus || 1;

  if (systemDelta === 0 || cpuDelta === 0) return 0;
  return (cpuDelta / systemDelta) * cpuCount * 100;
}

/**
 * Compute memory usage in bytes from a container stats snapshot.
 */
export function memoryUsage(stats: ContainerStats): number {
  return stats.memory_stats.usage || 0;
}

/**
 * Compute memory limit in bytes from a container stats snapshot.
 */
export function memoryLimit(stats: ContainerStats): number {
  return stats.memory_stats.limit || 0;
}

/**
 * Format memory as a human-readable string (e.g. "128.5 MiB / 1.0 GiB").
 */
export function formatMemory(stats: ContainerStats): string {
  const usage = memoryUsage(stats);
  const limit = memoryLimit(stats);
  return `${formatBytes(usage)} / ${formatBytes(limit)}`;
}

// ---------------------------------------------------------------------------
// Log stream demultiplexing
// ---------------------------------------------------------------------------

/**
 * Docker multiplexes stdout/stderr in non-TTY containers using an 8-byte
 * framing protocol per chunk:
 *
 *   Byte 0:     Stream type (1 = stdout, 2 = stderr)
 *   Bytes 1-3:  Reserved (null padding)
 *   Bytes 4-7:  Payload size (big-endian uint32)
 *   Remaining:  Payload bytes
 *
 * If we just call resp.text(), the binary headers appear as garbage
 * characters. This function strips the headers and concatenates the
 * payloads into a single string.
 *
 * For TTY containers, the response is raw text with no framing —
 * this function detects that and returns the text as-is.
 */
async function demuxLogStream(resp: Response): Promise<string> {
  if (!resp.body) return "";

  const reader = resp.body.getReader();
  const chunks: Uint8Array[] = [];
  let buffer = new Uint8Array(0);

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      // Append to buffer
      const next = new Uint8Array(buffer.length + value.length);
      next.set(buffer, 0);
      next.set(value, buffer.length);
      buffer = next;

      // Try to detect if this is a multiplexed stream.
      // A multiplexed stream starts with byte 1 or 2 (stdout/stderr),
      // followed by 3 null bytes. A raw text stream won't have that pattern.
      if (buffer.length >= 8) {
        const firstByte = buffer[0];
        const nullBytes = buffer[1] === 0 && buffer[2] === 0 && buffer[3] === 0;
        if ((firstByte === 1 || firstByte === 2) && nullBytes) {
          // Multiplexed stream — parse frames
          return parseMultiplexedBuffer(buffer, reader);
        } else {
          // Raw text stream (TTY container) — return as-is
          return new TextDecoder().decode(buffer);
        }
      }
    }

    // Less than 8 bytes — just return as text
    return new TextDecoder().decode(buffer);
  } finally {
    reader.releaseLock();
  }
}

/**
 * Parse a multiplexed Docker log stream from a buffer + reader.
 * Handles partial frames by buffering incomplete data.
 */
async function parseMultiplexedBuffer(
  initialBuffer: Uint8Array,
  reader: ReadableStreamDefaultReader<Uint8Array>,
): Promise<string> {
  const decoder = new TextDecoder();
  const outputParts: string[] = [];
  let buffer = initialBuffer;

  while (true) {
    // Need at least 8 bytes for the header
    while (buffer.length < 8) {
      const { done, value } = await reader.read();
      if (done) {
        // Return whatever we've parsed so far
        return outputParts.join("");
      }
      const next = new Uint8Array(buffer.length + value.length);
      next.set(buffer, 0);
      next.set(value, buffer.length);
      buffer = next;
    }

    // Parse header
    const streamType = buffer[0]; // 1=stdout, 2=stderr
    // Bytes 1-3 are reserved
    const payloadSize = (buffer[4] << 24) | (buffer[5] << 16) | (buffer[6] << 8) | buffer[7];

    if (payloadSize === 0) {
      // Empty frame — skip header
      buffer = buffer.slice(8);
      continue;
    }

    // Wait until we have the full payload
    while (buffer.length < 8 + payloadSize) {
      const { done, value } = await reader.read();
      if (done) {
        // Partial frame — decode what we have
        const available = buffer.slice(8);
        outputParts.push(decoder.decode(available, { stream: true }));
        return outputParts.join("");
      }
      const next = new Uint8Array(buffer.length + value.length);
      next.set(buffer, 0);
      next.set(value, buffer.length);
      buffer = next;
    }

    // Extract payload
    const payload = buffer.slice(8, 8 + payloadSize);
    outputParts.push(decoder.decode(payload, { stream: true }));

    // Remove processed frame from buffer
    buffer = buffer.slice(8 + payloadSize);
  }
}

// ---------------------------------------------------------------------------
// Port conflict detection
// ---------------------------------------------------------------------------

/** Describes a container port conflict detected from Docker Engine API data. */
export interface PortConflict {
  /** Conflicting published port. */
  port: number;
  /** ID of the container using the port. */
  containerId: string;
  /** Name of the container using the port. */
  containerName: string;
  /** Compose service name, if available. */
  serviceName: string | null;
  /** Compose project name, if available. */
  projectName: string | null;
}

/**
 * Find containers that are binding any of the specified ports.
 *
 * A single API call replaces N `docker ps --filter "publish=$port"` CLI
 * invocations. Returns a list of port conflicts with container details.
 *
 * @param client - Initialized Docker API client
 * @param ports - Array of port numbers to check
 * @param excludeProject - Optional compose project name to exclude (e.g. the current run)
 */
export async function findPortConflicts(
  client: DockerApiClient,
  ports: number[],
  excludeProject?: string,
): Promise<PortConflict[]> {
  const conflicts: PortConflict[] = [];
  const portSet = new Set(ports);

  const containers = await client.listContainers();

  for (const container of containers) {
    const projectName = composeProjectName(container);
    if (excludeProject && projectName === excludeProject) continue;

    for (const portBinding of container.Ports) {
      if (portBinding.PublicPort && portSet.has(portBinding.PublicPort)) {
        const serviceName = composeServiceName(container);
        const containerName = container.Names[0]?.replace(/^\//, "") ||
          container.Id.substring(0, 12);
        conflicts.push({
          port: portBinding.PublicPort,
          containerId: container.Id,
          containerName,
          serviceName,
          projectName,
        });
      }
    }
  }

  return conflicts;
}

/**
 * Find stale Docker Compose projects that are holding any of the specified ports.
 *
 * Returns a set of project names that can be torn down to free the ports.
 */
export async function findStaleProjectsOnPorts(
  client: DockerApiClient,
  ports: number[],
  excludeProject?: string,
): Promise<Set<string>> {
  const conflicts = await findPortConflicts(client, ports, excludeProject);
  const projects = new Set<string>();
  for (const conflict of conflicts) {
    if (conflict.projectName && conflict.projectName !== excludeProject) {
      projects.add(conflict.projectName);
    }
  }
  return projects;
}

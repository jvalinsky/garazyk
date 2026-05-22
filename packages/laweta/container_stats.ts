/**
 * Container resource stats sampler with OTel metric export.
 *
 * Periodically polls container CPU, memory, network, and block I/O
 * stats via the Docker Engine API and records them as OTel metrics
 * and span events. This gives you time-series resource usage visible
 * in SigNoz alongside your traces.
 *
 * Uses `?stream=false&one-shot=true` for fast single snapshots
 * rather than streaming (which ties up one connection per container).
 *
 * Zero-cost when OTel is not enabled — the sampler is never created.
 *
 * @module container_stats
 */

import {
  composeServiceName,
  type ContainerStats,
  type ContainerSummary,
  cpuPercent,
  type DockerApiClient,
  memoryLimit,
  memoryUsage,
} from "./docker_api.ts";
import {
  addSpanEvent,
  isOtelEnabled,
  type MetricAttributes,
  recordCounter,
  recordGauge,
} from "./telemetry.ts";
import { formatBytes } from "./format.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Options for `ContainerStatsSampler`. */
export interface StatsSamplerOptions {
  /** Docker API client (must be initialized). */
  client: DockerApiClient;
  /** Sampling interval in milliseconds. Default: 5000. */
  intervalMs?: number;
  /** Docker Compose project name to filter containers. */
  composeProject?: string;
  /** Callback when memory pressure is detected (failcnt increases). */
  onMemoryPressure?: (alert: MemoryPressureAlert) => void;
}

/** Memory pressure alert emitted when `failcnt` increases. */
export interface MemoryPressureAlert {
  /** Docker container name. */
  containerName: string;
  /** Docker Compose service name. */
  serviceName: string;
  /** Docker container ID. */
  containerId: string;
  /** Current memory fail count. */
  failcnt: number;
  /** Previous memory fail count. */
  previousFailcnt: number;
  /** Current memory usage in bytes. */
  memoryUsageBytes: number;
  /** Memory limit in bytes. */
  memoryLimitBytes: number;
  /** Memory usage as a percentage of the limit. */
  memoryPercent: number;
}

/** Snapshot of container resource usage collected during a sample. */
export interface ContainerStatsSnapshot {
  /** Docker container name. */
  containerName: string;
  /** Docker Compose service name. */
  serviceName: string;
  /** Docker container ID. */
  containerId: string;
  /** CPU usage percentage. */
  cpuPercent: number;
  /** Current memory usage in bytes. */
  memoryUsageBytes: number;
  /** Memory limit in bytes. */
  memoryLimitBytes: number;
  /** Memory usage as a percentage of the limit. */
  memoryPercent: number;
  /** Resident set size in bytes. */
  memoryRssBytes: number;
  /** Memory cache in bytes. */
  memoryCacheBytes: number;
  /** Memory fail count. */
  memoryFailcnt: number;
  /** Network receive bytes. */
  networkRxBytes: number;
  /** Network transmit bytes. */
  networkTxBytes: number;
  /** Network receive errors. */
  networkRxErrors: number;
  /** Network transmit errors. */
  networkTxErrors: number;
  /** Block I/O read bytes. */
  blockioReadBytes: number;
  /** Block I/O write bytes. */
  blockioWriteBytes: number;
  /** Number of container processes. */
  pids: number;
  /** Snapshot timestamp in milliseconds since epoch. */
  timestamp: number;
}

// ---------------------------------------------------------------------------
// ContainerStatsSampler
// ---------------------------------------------------------------------------

/** Periodically samples container stats and records OTel metrics. */
export class ContainerStatsSampler {
  private client: DockerApiClient;
  private intervalMs: number;
  private composeProject: string;
  private onMemoryPressure?: (alert: MemoryPressureAlert) => void;
  private running = false;
  private timerId: ReturnType<typeof setInterval> | null = null;
  private sampleInFlight: Promise<ContainerStatsSnapshot[]> | null = null;
  private previousFailcnt = new Map<string, number>();
  private previousCounters = new Map<string, number>();

  /**
   * Create a stats sampler.
   * @param opts - Sampler options.
   */
  constructor(opts: StatsSamplerOptions) {
    this.client = opts.client;
    this.intervalMs = opts.intervalMs ?? 5000;
    this.composeProject = opts.composeProject ?? "";
    this.onMemoryPressure = opts.onMemoryPressure;
  }

  /**
   * Start the periodic sampling loop.
   *
   * Samples all containers in the compose project every `intervalMs`
   * and records metrics via OTel.
   */
  start(): void {
    if (this.running) return;
    this.running = true;
    this.timerId = setInterval(
      () => this.runScheduledSample(),
      this.intervalMs,
    );
    // Fire an initial sample immediately
    this.runScheduledSample();
  }

  /**
   * Stop the sampling loop.
   *
   * Records a final snapshot of all containers before stopping.
   */
  async stop(): Promise<void> {
    const wasRunning = this.running;
    const scheduledSample = this.sampleInFlight;
    if (!wasRunning && scheduledSample === null) return;
    this.running = false;
    if (this.timerId !== null) {
      clearInterval(this.timerId);
      this.timerId = null;
    }
    if (scheduledSample !== null) {
      await scheduledSample;
    }
    // Record one final snapshot
    await this.sample();
  }

  /**
   * Take a single snapshot of all containers and record metrics.
   *
   * Collects data regardless of whether OTel is enabled, but only
   * records OTel metrics when enabled. This allows tests to verify
   * data collection without requiring an OTel backend.
   */
  async sample(): Promise<ContainerStatsSnapshot[]> {
    const snapshots: ContainerStatsSnapshot[] = [];

    try {
      const containers = await this.client.listContainers();
      const projectContainers = containers.filter((c) => {
        const project = c.Labels?.["com.docker.compose.project"] ?? "";
        return !this.composeProject || project === this.composeProject;
      });

      for (const container of projectContainers) {
        try {
          const stats = await this.client.containerStats(container.Id, {
            oneShot: true,
          });
          const snapshot = this.buildSnapshot(container, stats);
          snapshots.push(snapshot);
          if (isOtelEnabled()) {
            this.recordMetrics(snapshot);
          }
          this.checkMemoryPressure(container, stats);
        } catch {
          // Container may have stopped between list and stats
        }
      }
    } catch {
      // Docker API may be temporarily unavailable
    }

    return snapshots;
  }

  /**
   * Build a snapshot from a container summary and its stats.
   */
  private buildSnapshot(
    container: ContainerSummary,
    stats: ContainerStats,
  ): ContainerStatsSnapshot {
    const serviceName = composeServiceName(container) ??
      container.Names?.[0]?.replace(/^\//, "") ??
      "unknown";
    const containerName = container.Names?.[0]?.replace(/^\//, "") ??
      container.Id.substring(0, 12);
    const memUsage = memoryUsage(stats);
    const memLimit = memoryLimit(stats);
    const memPercent = memLimit > 0 ? (memUsage / memLimit) * 100 : 0;

    // Aggregate network stats across all interfaces
    let netRx = 0, netTx = 0, netRxErr = 0, netTxErr = 0;
    if (stats.networks) {
      for (const iface of Object.values(stats.networks)) {
        netRx += iface.rx_bytes;
        netTx += iface.tx_bytes;
        netRxErr += iface.rx_errors;
        netTxErr += iface.tx_errors;
      }
    }

    // Aggregate block I/O
    let blkRead = 0, blkWrite = 0;
    if (stats.blkio_stats?.io_service_bytes_recursive) {
      for (const entry of stats.blkio_stats.io_service_bytes_recursive) {
        if (entry.op === "read") blkRead += entry.value;
        else if (entry.op === "write") blkWrite += entry.value;
      }
    }

    return {
      containerName,
      serviceName,
      containerId: container.Id,
      cpuPercent: cpuPercent(stats),
      memoryUsageBytes: memUsage,
      memoryLimitBytes: memLimit,
      memoryPercent: memPercent,
      memoryRssBytes: stats.memory_stats?.stats?.rss ?? 0,
      memoryCacheBytes: stats.memory_stats?.stats?.cache ?? 0,
      memoryFailcnt: stats.memory_stats?.failcnt ?? 0,
      networkRxBytes: netRx,
      networkTxBytes: netTx,
      networkRxErrors: netRxErr,
      networkTxErrors: netTxErr,
      blockioReadBytes: blkRead,
      blockioWriteBytes: blkWrite,
      pids: stats.num_procs ?? 0,
      timestamp: Date.now(),
    };
  }

  /**
   * Record a snapshot as OTel metrics and a span event.
   *
   * Only called when OTel is enabled.
   */
  private recordMetrics(s: ContainerStatsSnapshot): void {
    const attrs: MetricAttributes = {
      "container.name": s.containerName,
      "container.service": s.serviceName,
    };

    // Gauges (point-in-time values) — fire-and-forget
    recordGauge("container.cpu.percent", s.cpuPercent, attrs).catch(() => {});
    recordGauge("container.memory.usage_bytes", s.memoryUsageBytes, attrs)
      .catch(() => {});
    recordGauge("container.memory.limit_bytes", s.memoryLimitBytes, attrs)
      .catch(() => {});
    recordGauge("container.memory.percent", s.memoryPercent, attrs).catch(
      () => {},
    );
    recordGauge("container.memory.rss_bytes", s.memoryRssBytes, attrs).catch(
      () => {},
    );
    recordGauge("container.memory.cache_bytes", s.memoryCacheBytes, attrs)
      .catch(() => {});
    recordGauge("container.pids", s.pids, attrs).catch(() => {});

    this.recordCounterDelta(
      "container.memory.failcnt",
      s.containerId,
      s.memoryFailcnt,
      attrs,
    );
    this.recordCounterDelta(
      "container.network.rx_bytes",
      s.containerId,
      s.networkRxBytes,
      attrs,
    );
    this.recordCounterDelta(
      "container.network.tx_bytes",
      s.containerId,
      s.networkTxBytes,
      attrs,
    );
    this.recordCounterDelta(
      "container.network.rx_errors",
      s.containerId,
      s.networkRxErrors,
      attrs,
    );
    this.recordCounterDelta(
      "container.network.tx_errors",
      s.containerId,
      s.networkTxErrors,
      attrs,
    );
    this.recordCounterDelta(
      "container.blockio.read_bytes",
      s.containerId,
      s.blockioReadBytes,
      attrs,
    );
    this.recordCounterDelta(
      "container.blockio.write_bytes",
      s.containerId,
      s.blockioWriteBytes,
      attrs,
    );

    // Span event for correlation with traces
    addSpanEvent("container.stats", {
      "container.name": s.containerName,
      "container.service": s.serviceName,
      "container.cpu_percent": s.cpuPercent.toFixed(1),
      "container.memory_percent": s.memoryPercent.toFixed(1),
      "container.memory_usage": formatBytes(s.memoryUsageBytes),
      "container.memory_limit": formatBytes(s.memoryLimitBytes),
      "container.pids": s.pids,
    });
  }

  /** Run a scheduled stat collection sampling cycle. */
  private runScheduledSample(): void {
    if (this.sampleInFlight !== null) return;
    const sample = this.sample().catch((e) => {
      console.debug("[container-stats] scheduled sample failed", e);
      return [];
    });
    this.sampleInFlight = sample;
    sample.finally(() => {
      if (this.sampleInFlight === sample) {
        this.sampleInFlight = null;
      }
    });
  }

  /** Compute and record the delta value for a counter metric. */
  private recordCounterDelta(
    metricName: string,
    containerId: string,
    currentValue: number,
    attrs: MetricAttributes,
  ): void {
    const key = `${containerId}:${metricName}`;
    const previousValue = this.previousCounters.get(key);
    this.previousCounters.set(key, currentValue);

    if (previousValue === undefined || currentValue <= previousValue) {
      return;
    }

    recordCounter(metricName, currentValue - previousValue, attrs).catch(
      () => {},
    );
  }

  /**
   * Check for memory pressure (failcnt increases).
   *
   * `failcnt` increments each time the container exceeds its memory
   * limit and the kernel reclaims memory. If it keeps increasing,
   * the OOM killer is about to fire.
   */
  private checkMemoryPressure(
    container: ContainerSummary,
    stats: ContainerStats,
  ): void {
    const failcnt = stats.memory_stats?.failcnt ?? 0;
    const prev = this.previousFailcnt.get(container.Id) ?? 0;

    if (failcnt > prev && prev >= 0) {
      const serviceName = composeServiceName(container) ?? "unknown";
      const containerName = container.Names?.[0]?.replace(/^\//, "") ??
        container.Id.substring(0, 12);
      const memUsage = memoryUsage(stats);
      const memLimit = memoryLimit(stats);

      const alert: MemoryPressureAlert = {
        containerName,
        serviceName,
        containerId: container.Id,
        failcnt,
        previousFailcnt: prev,
        memoryUsageBytes: memUsage,
        memoryLimitBytes: memLimit,
        memoryPercent: memLimit > 0 ? (memUsage / memLimit) * 100 : 0,
      };

      // Record as a span event for trace correlation
      addSpanEvent("container.memory_pressure", {
        "container.name": containerName,
        "container.service": serviceName,
        "container.failcnt": failcnt,
        "container.memory_percent": alert.memoryPercent.toFixed(1),
        "container.memory_usage": formatBytes(memUsage),
        "container.memory_limit": formatBytes(memLimit),
      }).catch(() => {});

      // Fire callback
      this.onMemoryPressure?.(alert);
    }

    this.previousFailcnt.set(container.Id, failcnt);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

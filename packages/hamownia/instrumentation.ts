/** Operation timing, metrics scraping, storage monitoring, and instrumentation reports. @module instrumentation */
import { join } from "@std/path";

const SAMPLE_INTERVAL = 2000; // ms

/** A metrics sample captured at a specific point in time. */
export interface MetricsSample {
  /** Sample timestamp in seconds since the Unix epoch. */
  timestamp: number;
  /** Metric values captured for the sample. */
  metrics: Record<string, number>;
}

/** Tracks operation counts and duration distribution (min, max, mean, percentiles). */
export class OperationStats {
  /** Number of recorded durations. */
  public count = 0;
  private durations: number[] = [];

  /**
   * @param name - Operation name.
   */
  constructor(
    public name: string,
  ) {}

  /**
   * Records a duration measurement in milliseconds.
   * @param durationMs - Duration in milliseconds.
   */
  record(durationMs: number) {
    this.count++;
    this.durations.push(durationMs);
  }

  /**
   * Minimum recorded duration in milliseconds.
   * @returns The minimum recorded duration.
   */
  get min(): number {
    if (this.durations.length === 0) return 0;
    return Math.min(...this.durations);
  }
  /**
   * Maximum recorded duration in milliseconds.
   * @returns The maximum recorded duration.
   */
  get max(): number {
    return Math.max(...this.durations, 0);
  }
  /**
   * Mean recorded duration in milliseconds.
   * @returns The mean recorded duration.
   */
  get mean(): number {
    if (this.durations.length === 0) return 0;
    return this.durations.reduce((a, b) => a + b, 0) / this.durations.length;
  }

  /**
   * Returns the requested percentile duration in milliseconds.
   * @param p - Percentile to calculate.
   * @returns The requested percentile duration.
   */
  percentile(p: number): number {
    if (this.durations.length === 0) return 0;
    const sorted = [...this.durations].sort((a, b) => a - b);
    const idx = Math.min(
      Math.floor(sorted.length * p / 100),
      sorted.length - 1,
    );
    return sorted[idx];
  }

  /**
   * 50th percentile duration in milliseconds.
   * @returns The 50th percentile duration.
   */
  get p50(): number {
    return this.percentile(50);
  }
  /**
   * 95th percentile duration in milliseconds.
   * @returns The 95th percentile duration.
   */
  get p95(): number {
    return this.percentile(95);
  }
  /**
   * 99th percentile duration in milliseconds.
   * @returns The 99th percentile duration.
   */
  get p99(): number {
    return this.percentile(99);
  }

  /**
   * Total recorded duration in milliseconds.
   * @returns The total recorded duration.
   */
  get totalMs(): number {
    return this.durations.reduce((a, b) => a + b, 0);
  }

  /**
   * Returns a plain object summary of the operation statistics.
   * @returns A serializable summary of the operation statistics.
   */
  toDict(): Record<string, unknown> {
    return {
      name: this.name,
      count: this.count,
      min_ms: Number(this.min.toFixed(2)),
      max_ms: Number(this.max.toFixed(2)),
      mean_ms: Number(this.mean.toFixed(2)),
      p50_ms: Number(this.p50.toFixed(2)),
      p95_ms: Number(this.p95.toFixed(2)),
      p99_ms: Number(this.p99.toFixed(2)),
    };
  }
}

/** Measures duration of named async operations and collects timing stats. */
export class OperationTimer {
  private stats: Record<string, OperationStats> = {};

  /**
   * Measures an async operation and records its duration.
   * @typeParam T - Result type returned by the measured function.
   * @param name - Operation name.
   * @param fn - Async function to execute.
   * @returns The resolved value returned by the measured function.
   */
  async measure<T>(name: string, fn: () => Promise<T>): Promise<T> {
    const start = performance.now();
    try {
      return await fn();
    } finally {
      const duration = performance.now() - start;
      if (!this.stats[name]) this.stats[name] = new OperationStats(name);
      this.stats[name].record(duration);
    }
  }

  /**
   * Returns the recorded stats for a named operation.
   * @param name - Operation name.
   * @returns The recorded operation stats, or undefined if none exist.
   */
  getStats(name: string): OperationStats {
    return this.stats[name];
  }

  /**
   * Returns all recorded operation stats.
   * @returns A map of operation names to stats objects.
   */
  getAllStats(): Record<string, OperationStats> {
    return this.stats;
  }

  /**
   * Returns all operation stats as plain objects.
   * @returns A map of operation names to serialized stats.
   */
  toDict(): Record<string, unknown> {
    const res: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(this.stats)) {
      res[k] = v.toDict();
    }
    return res;
  }
}

/** Tracks the duration of named execution phases. */
export class PhaseTimer {
  private phases: Record<string, number> = {};
  private currentPhase: string | null = null;
  private currentStart = 0;

  /**
   * Starts tracking a named phase.
   * @param name - Phase name.
   */
  startPhase(name: string) {
    this.currentPhase = name;
    this.currentStart = performance.now();
  }

  /** Ends the current phase and records its duration in seconds. */
  endPhase() {
    if (this.currentPhase) {
      this.phases[this.currentPhase] = (performance.now() - this.currentStart) /
        1000;
      this.currentPhase = null;
    }
  }

  /**
   * Returns the recorded phase timings.
   * @returns A map of phase names to durations in seconds.
   */
  toDict(): Record<string, unknown> {
    return { ...this.phases };
  }
}

/** A time-series entry for a single metric. */
export interface MetricSeriesEntry {
  metric_name: string;
  samples: Array<[number, number]>;
}

/** Periodically scrapes Prometheus metrics endpoints and records time-series data. */
export class PrometheusScraper {
  private samples: Record<string, MetricsSample[]> = {};
  private intervalId?: number;

  constructor(private endpoints: Record<string, string>) {
    for (const name of Object.keys(endpoints)) {
      this.samples[name] = [];
    }
  }

  /** Starts periodic scraping for all configured endpoints. */
  start() {
    this.intervalId = setInterval(() => this.scrape(), SAMPLE_INTERVAL);
  }

  /**
   * Stops scraping, performs one final scrape, and returns the collected time series.
   * @returns The aggregated metric time series.
   */
  async stop(): Promise<Record<string, MetricSeriesEntry>> {
    if (this.intervalId) clearInterval(this.intervalId);
    await this.scrape(); // Final scrape
    return this.getTimeSeries();
  }

  private async scrape() {
    for (const [name, url] of Object.entries(this.endpoints)) {
      try {
        const res = await fetch(url);
        const text = await res.text();
        const metrics = this.parsePrometheus(text);
        this.samples[name].push({ timestamp: Date.now() / 1000, metrics });
      } catch {
        // Ignore errors
      }
    }
  }

  private parsePrometheus(text: string): Record<string, number> {
    const metrics: Record<string, number> = {};
    for (const line of text.split("\n")) {
      if (!line || line.startsWith("#")) continue;
      const match = line.match(
        /^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+([0-9eE.+-]+)$/,
      );
      if (match) {
        const key = match[1] + (match[2] || "");
        metrics[key] = parseFloat(match[3]);
      }
    }
    return metrics;
  }

  /**
   * Returns the collected metric time series.
   * @returns A map of metric names to timestamped samples.
   */
  getTimeSeries(): Record<string, MetricSeriesEntry> {
    const res: Record<string, MetricSeriesEntry> = {};
    for (const samples of Object.values(this.samples)) {
      for (const sample of samples) {
        for (const [key, val] of Object.entries(sample.metrics)) {
          if (!res[key]) {
            res[key] = { metric_name: key, samples: [] };
          }
          res[key].samples.push([sample.timestamp, val]);
        }
      }
    }
    return res;
  }
}

/** Periodically samples database and WAL file sizes at configured paths. */
export class StorageMonitor {
  private stats: Record<string, unknown[]> = {};
  private intervalId?: number;

  constructor(private paths: Record<string, string[]>) {
    for (const label of Object.keys(paths)) {
      this.stats[label] = [];
    }
  }

  /** Starts periodic storage sampling for all configured paths. */
  start() {
    this.intervalId = setInterval(() => this.sample(), SAMPLE_INTERVAL);
  }

  /**
   * Stops sampling, performs one final sample, and returns the collected stats.
   * @returns The collected storage statistics.
   */
  async stop(): Promise<Record<string, unknown[]>> {
    if (this.intervalId) clearInterval(this.intervalId);
    await this.sample();
    return this.stats;
  }

  private async sample() {
    for (const [label, paths] of Object.entries(this.paths)) {
      let dbSize = 0;
      let walSize = 0;
      for (const path of paths) {
        try {
          const info = await Deno.stat(path);
          if (path.endsWith("-wal")) walSize += info.size;
          else dbSize += info.size;
        } catch { /* ignore */ }
      }
      this.stats[label].push({
        timestamp: Date.now() / 1000,
        db_size_bytes: dbSize,
        wal_size_bytes: walSize,
        total_bytes: dbSize + walSize,
      });
    }
  }
}

/** Aggregate report combining operation stats, metrics, process stats, and storage data. */
export class InstrumentationReport {
  /**
   * @param operationStats - Operation statistics keyed by name.
   * @param metricsTimeSeries - Scraped metric time series keyed by metric name.
   * @param processStats - Process statistics for the current runtime.
   * @param storageStats - Storage statistics keyed by label.
   * @param phaseTimings - Phase timings in seconds keyed by phase name.
   */
  constructor(
    public operationStats: Record<string, unknown>,
    public metricsTimeSeries: Record<string, unknown>,
    public processStats: Record<string, unknown>,
    public storageStats: Record<string, unknown>,
    public phaseTimings: Record<string, unknown>,
  ) {}

  /**
   * Returns the report as a plain object.
   * @returns A serializable instrumentation report.
   */
  toDict(): Record<string, unknown> {
    return {
      operations: this.operationStats,
      metrics: this.metricsTimeSeries,
      process: this.processStats,
      storage: this.storageStats,
      phase_timings: this.phaseTimings,
    };
  }

  /**
   * Writes the report as formatted JSON.
   * @param path - Output file path.
   */
  async writeJson(path: string): Promise<void> {
    await Deno.mkdir(join(path, ".."), { recursive: true });
    await Deno.writeTextFile(path, JSON.stringify(this.toDict(), null, 2));
  }
}

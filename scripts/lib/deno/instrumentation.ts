import { join } from "@std/path";
import { exists } from "@std/fs";

const SAMPLE_INTERVAL = 2000; // ms

export interface MetricsSample {
  timestamp: number;
  metrics: Record<string, number>;
}

export class OperationStats {
  public count = 0;
  private durations: number[] = [];

  constructor(public name: string) {}

  record(durationMs: number) {
    this.count++;
    this.durations.push(durationMs);
  }

  get min() { return Math.min(...this.durations, 0); }
  get max() { return Math.max(...this.durations, 0); }
  get mean() {
    if (this.durations.length === 0) return 0;
    return this.durations.reduce((a, b) => a + b, 0) / this.durations.length;
  }

  percentile(p: number) {
    if (this.durations.length === 0) return 0;
    const sorted = [...this.durations].sort((a, b) => a - b);
    const idx = Math.min(Math.floor(sorted.length * p / 100), sorted.length - 1);
    return sorted[idx];
  }

  get p50() { return this.percentile(50); }
  get p95() { return this.percentile(95); }
  get p99() { return this.percentile(99); }

  get totalMs() { return this.durations.reduce((a, b) => a + b, 0); }

  toDict() {
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

export class OperationTimer {
  private stats: Record<string, OperationStats> = {};

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

  getStats(name: string) {
    return this.stats[name];
  }

  getAllStats() {
    return this.stats;
  }

  toDict() {
    const res: Record<string, any> = {};
    for (const [k, v] of Object.entries(this.stats)) {
      res[k] = v.toDict();
    }
    return res;
  }
}

export class PhaseTimer {
  private phases: Record<string, number> = {};
  private currentPhase: string | null = null;
  private currentStart = 0;

  startPhase(name: string) {
    this.currentPhase = name;
    this.currentStart = performance.now();
  }

  endPhase() {
    if (this.currentPhase) {
      this.phases[this.currentPhase] = (performance.now() - this.currentStart) / 1000;
      this.currentPhase = null;
    }
  }

  toDict() {
    return { ...this.phases };
  }
}

export class PrometheusScraper {
  private samples: Record<string, MetricsSample[]> = {};
  private intervalId?: number;

  constructor(private endpoints: Record<string, string>) {
    for (const name of Object.keys(endpoints)) {
      this.samples[name] = [];
    }
  }

  start() {
    this.intervalId = setInterval(() => this.scrape(), SAMPLE_INTERVAL);
  }

  async stop() {
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
      const match = line.match(/^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+([0-9eE.+-]+)$/);
      if (match) {
        const key = match[1] + (match[2] || "");
        metrics[key] = parseFloat(match[3]);
      }
    }
    return metrics;
  }

  getTimeSeries() {
    const res: Record<string, any> = {};
    for (const samples of Object.values(this.samples)) {
      for (const sample of samples) {
        for (const [key, val] of Object.entries(sample.metrics)) {
          if (!res[key]) res[key] = { metric_name: key, samples: [] };
          res[key].samples.push([sample.timestamp, val]);
        }
      }
    }
    return res;
  }
}

export class StorageMonitor {
  private stats: Record<string, any[]> = {};
  private intervalId?: number;

  constructor(private paths: Record<string, string[]>) {
    for (const label of Object.keys(paths)) {
      this.stats[label] = [];
    }
  }

  start() {
    this.intervalId = setInterval(() => this.sample(), SAMPLE_INTERVAL);
  }

  async stop() {
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

export class InstrumentationReport {
  constructor(
    public operationStats: Record<string, any>,
    public metricsTimeSeries: Record<string, any>,
    public processStats: Record<string, any>,
    public storageStats: Record<string, any>,
    public phaseTimings: Record<string, number>
  ) {}

  toDict() {
    return {
      operations: this.operationStats,
      metrics: this.metricsTimeSeries,
      process: this.processStats,
      storage: this.storageStats,
      phase_timings: this.phaseTimings,
    };
  }

  async writeJson(path: string) {
    await Deno.mkdir(join(path, ".."), { recursive: true });
    await Deno.writeTextFile(path, JSON.stringify(this.toDict(), null, 2));
  }
}

/**
 * Tests for the ContainerStatsSampler.
 *
 * These tests use a mock DockerApiClient to verify the sampler's
 * logic without requiring a running Docker daemon.
 */

import {
  ContainerStatsSampler,
  type MemoryPressureAlert,
} from "./container_stats.ts";
import type {
  ContainerStats,
  ContainerSummary,
  DockerApiClient,
} from "./docker_api.ts";
import { setTelemetryTestHook } from "./telemetry.ts";
import { assertEquals } from "@std/assert";

// ---------------------------------------------------------------------------
// Mock Docker API client
// ---------------------------------------------------------------------------

function makeMockClient(
  containers: ContainerSummary[],
  stats: ContainerStats,
): DockerApiClient {
  return {
    // deno-lint-ignore no-explicit-any
    client: {} as any,
    _socketPath: "/mock",
    _available: true,
    _baseUrl: "http://localhost/v1.45",
    get available() {
      return true;
    },
    init() {
      return Promise.resolve(true);
    },
    close() {},
    ping() {
      return Promise.resolve(true);
    },
    version() {
      // deno-lint-ignore no-explicit-any
      return Promise.resolve({} as any);
    },
    listContainers() {
      return Promise.resolve(containers);
    },
    inspectContainer() {
      // deno-lint-ignore no-explicit-any
      return Promise.resolve({} as any);
    },
    containerLogs() {
      return Promise.resolve(new ReadableStream());
    },
    containerStats(_id: string, _opts?: { oneShot?: boolean }) {
      return Promise.resolve(stats);
    },
    waitContainer() {
      return Promise.resolve({ StatusCode: 0 });
    },
    async *streamEvents() {},
    async *streamContainerStats() {},
  } as unknown as DockerApiClient;
}

function makeContainerSummary(
  overrides: Partial<ContainerSummary> = {},
): ContainerSummary {
  return {
    Id: "abc123def456",
    Names: ["/local-pds"],
    Image: "garazyk/pds:latest",
    State: "running",
    Status: "Up 5 minutes",
    Labels: {
      "com.docker.compose.project": "garazyk-e2e-test",
      "com.docker.compose.service": "local-pds",
    },
    ...overrides,
  } as unknown as ContainerSummary;
}

function makeContainerStats(
  overrides: Partial<ContainerStats> = {},
): ContainerStats {
  return {
    read: new Date().toISOString(),
    preread: new Date().toISOString(),
    num_procs: 12,
    cpu_stats: {
      cpu_usage: {
        total_usage: 500000000,
        percpu_usage: [250000000, 250000000],
        usage_in_kernelmode: 100000000,
        usage_in_usermode: 400000000,
      },
      system_cpu_usage: 10000000000,
      online_cpus: 2,
      throttling_data: { periods: 0, throttled_periods: 0, throttled_time: 0 },
    },
    precpu_stats: {
      cpu_usage: {
        total_usage: 400000000,
        percpu_usage: [200000000, 200000000],
        usage_in_kernelmode: 80000000,
        usage_in_usermode: 320000000,
      },
      system_cpu_usage: 9900000000,
      online_cpus: 2,
      throttling_data: { periods: 0, throttled_periods: 0, throttled_time: 0 },
    },
    memory_stats: {
      usage: 128 * 1024 * 1024, // 128 MiB
      max_usage: 150 * 1024 * 1024,
      limit: 512 * 1024 * 1024, // 512 MiB
      stats: { cache: 20 * 1024 * 1024, rss: 108 * 1024 * 1024 },
      failcnt: 0,
    },
    blkio_stats: {
      io_service_bytes_recursive: [
        { major: 8, minor: 0, op: "read", value: 1024000 },
        { major: 8, minor: 0, op: "write", value: 512000 },
      ],
    },
    networks: {
      eth0: {
        rx_bytes: 1000000,
        rx_packets: 5000,
        rx_errors: 0,
        rx_dropped: 0,
        tx_bytes: 2000000,
        tx_packets: 3000,
        tx_errors: 0,
        tx_dropped: 0,
      },
    },
    ...overrides,
  } as ContainerStats;
}

function makeSequencedMockClient(
  containers: ContainerSummary[],
  statsSequence: ContainerStats[],
): DockerApiClient {
  let index = 0;
  return {
    listContainers() {
      return Promise.resolve(containers);
    },
    containerStats() {
      const stats = statsSequence[Math.min(index, statsSequence.length - 1)];
      index += 1;
      return Promise.resolve(stats);
    },
  } as unknown as DockerApiClient;
}

interface Deferred<T> {
  promise: Promise<T>;
  resolve: (value: T) => void;
}

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

interface RecordedMetric {
  name: string;
  value: number;
}

async function withTelemetryCapture(
  fn: (metrics: {
    gauges: RecordedMetric[];
    counters: RecordedMetric[];
  }) => Promise<void>,
): Promise<void> {
  const previousOtel = Deno.env.get("OTEL_DENO");
  const metrics = {
    gauges: [] as RecordedMetric[],
    counters: [] as RecordedMetric[],
  };

  Deno.env.set("OTEL_DENO", "true");
  setTelemetryTestHook({
    recordGauge(name, value) {
      metrics.gauges.push({ name, value });
    },
    recordCounter(name, value) {
      metrics.counters.push({ name, value });
    },
  });

  try {
    await fn(metrics);
  } finally {
    setTelemetryTestHook(null);
    if (previousOtel === undefined) {
      Deno.env.delete("OTEL_DENO");
    } else {
      Deno.env.set("OTEL_DENO", previousOtel);
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("buildSnapshot: computes correct CPU and memory percentages", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats();
  const client = makeMockClient([container], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
  });

  const snapshots = await sampler.sample();
  assertEquals(snapshots.length, 1);

  const s = snapshots[0];
  assertEquals(s.containerName, "local-pds");
  assertEquals(s.serviceName, "local-pds");
  assertEquals(s.pids, 12);
  assertEquals(s.memoryUsageBytes, 128 * 1024 * 1024);
  assertEquals(s.memoryLimitBytes, 512 * 1024 * 1024);
  assertEquals(s.memoryRssBytes, 108 * 1024 * 1024);
  assertEquals(s.memoryCacheBytes, 20 * 1024 * 1024);
  assertEquals(s.memoryFailcnt, 0);
  assertEquals(s.networkRxBytes, 1000000);
  assertEquals(s.networkTxBytes, 2000000);
  assertEquals(s.blockioReadBytes, 1024000);
  assertEquals(s.blockioWriteBytes, 512000);

  // Memory percent should be 128/512 * 100 = 25%
  assertEquals(s.memoryPercent, 25);
});

Deno.test("buildSnapshot: filters by compose project", async () => {
  const container1 = makeContainerSummary({
    Id: "aaa",
    Names: ["/local-pds"],
    Labels: {
      "com.docker.compose.project": "garazyk-e2e-test",
      "com.docker.compose.service": "local-pds",
    },
  });
  const container2 = makeContainerSummary({
    Id: "bbb",
    Names: ["/other-service"],
    Labels: {
      "com.docker.compose.project": "other-project",
      "com.docker.compose.service": "other",
    },
  });

  const stats = makeContainerStats();
  const client = makeMockClient([container1, container2], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
  });

  const snapshots = await sampler.sample();
  assertEquals(snapshots.length, 1);
  assertEquals(snapshots[0].containerId, "aaa");
});

Deno.test("buildSnapshot: aggregates network stats across interfaces", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats({
    networks: {
      eth0: {
        rx_bytes: 1000,
        rx_packets: 10,
        rx_errors: 0,
        rx_dropped: 0,
        tx_bytes: 2000,
        tx_packets: 20,
        tx_errors: 0,
        tx_dropped: 0,
      },
      eth1: {
        rx_bytes: 3000,
        rx_packets: 30,
        rx_errors: 1,
        rx_dropped: 0,
        tx_bytes: 4000,
        tx_packets: 40,
        tx_errors: 2,
        tx_dropped: 0,
      },
    },
  });
  const client = makeMockClient([container], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
  });

  const snapshots = await sampler.sample();
  assertEquals(snapshots[0].networkRxBytes, 4000);
  assertEquals(snapshots[0].networkTxBytes, 6000);
  assertEquals(snapshots[0].networkRxErrors, 1);
  assertEquals(snapshots[0].networkTxErrors, 2);
});

Deno.test("buildSnapshot: aggregates block I/O by operation type", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats({
    blkio_stats: {
      io_service_bytes_recursive: [
        { major: 8, minor: 0, op: "read", value: 1000 },
        { major: 8, minor: 0, op: "write", value: 2000 },
        { major: 8, minor: 1, op: "read", value: 3000 },
        { major: 8, minor: 1, op: "write", value: 4000 },
      ],
    },
  });
  const client = makeMockClient([container], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
  });

  const snapshots = await sampler.sample();
  assertEquals(snapshots[0].blockioReadBytes, 4000);
  assertEquals(snapshots[0].blockioWriteBytes, 6000);
});

Deno.test("memory pressure: fires callback when failcnt increases", async () => {
  const container = makeContainerSummary();
  let alertFired = false;
  let receivedAlert: MemoryPressureAlert | null = null;

  const client = makeMockClient(
    [container],
    makeContainerStats({
      memory_stats: {
        usage: 500000000,
        max_usage: 500000000,
        limit: 512000000,
        stats: { cache: 0, rss: 500000000 },
        failcnt: 0,
      },
    }),
  );

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
    onMemoryPressure: (alert) => {
      alertFired = true;
      receivedAlert = alert;
    },
  });

  // First sample — failcnt = 0, no alert
  await sampler.sample();
  assertEquals(alertFired, false);

  // Second sample — failcnt increases to 3
  const client2 = makeMockClient(
    [container],
    makeContainerStats({
      memory_stats: {
        usage: 510000000,
        max_usage: 510000000,
        limit: 512000000,
        stats: { cache: 0, rss: 510000000 },
        failcnt: 3,
      },
    }),
  );
  // deno-lint-ignore no-explicit-any
  (sampler as any).client = client2;

  await sampler.sample();
  assertEquals(alertFired, true);
  assertEquals(receivedAlert!.failcnt, 3);
  assertEquals(receivedAlert!.previousFailcnt, 0);
  assertEquals(receivedAlert!.serviceName, "local-pds");
});

Deno.test("memory pressure: does not fire when failcnt stays at 0", async () => {
  const container = makeContainerSummary();
  let alertFired = false;

  const stats = makeContainerStats({
    memory_stats: {
      usage: 128000000,
      max_usage: 150000000,
      limit: 512000000,
      stats: { cache: 20000000, rss: 108000000 },
      failcnt: 0,
    },
  });
  const client = makeMockClient([container], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
    onMemoryPressure: () => {
      alertFired = true;
    },
  });

  await sampler.sample();
  await sampler.sample();
  assertEquals(alertFired, false);
});

Deno.test("sampler: timer samples do not run concurrently", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats();
  let activeSamples = 0;
  let maxActiveSamples = 0;

  const client = {
    listContainers() {
      return Promise.resolve([container]);
    },
    async containerStats() {
      activeSamples += 1;
      maxActiveSamples = Math.max(maxActiveSamples, activeSamples);
      await delay(30);
      activeSamples -= 1;
      return stats;
    },
  } as unknown as DockerApiClient;

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
    intervalMs: 1,
  });

  sampler.start();
  await delay(10);
  await sampler.stop();

  assertEquals(maxActiveSamples, 1);
});

Deno.test("sampler: direct sample can run while scheduled sample is in flight", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats();
  const firstSample = deferred<ContainerStats>();
  let calls = 0;
  let activeSamples = 0;
  let maxActiveSamples = 0;

  const client = {
    listContainers() {
      return Promise.resolve([container]);
    },
    async containerStats() {
      calls += 1;
      activeSamples += 1;
      maxActiveSamples = Math.max(maxActiveSamples, activeSamples);
      if (calls === 1) {
        await firstSample.promise;
      }
      activeSamples -= 1;
      return stats;
    },
  } as unknown as DockerApiClient;

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
    intervalMs: 1000,
  });

  sampler.start();
  await delay(0);
  const directSample = sampler.sample();
  await delay(0);

  assertEquals(maxActiveSamples, 2);
  firstSample.resolve(stats);
  await directSample;
  await sampler.stop();
});

Deno.test("sampler: stop waits for scheduled sample and records one final sample", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats();
  const firstSample = deferred<ContainerStats>();
  let calls = 0;

  const client = {
    listContainers() {
      return Promise.resolve([container]);
    },
    async containerStats() {
      calls += 1;
      if (calls === 1) {
        await firstSample.promise;
      }
      return stats;
    },
  } as unknown as DockerApiClient;

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
    intervalMs: 1000,
  });

  sampler.start();
  await delay(0);
  const stop = sampler.stop();
  await delay(0);
  assertEquals(calls, 1);

  firstSample.resolve(stats);
  await stop;
  assertEquals(calls, 2);
  await sampler.stop();
  assertEquals(calls, 2);
});

Deno.test("telemetry: first sample emits gauges but no counter deltas", async () => {
  await withTelemetryCapture(async (metrics) => {
    const container = makeContainerSummary();
    const client = makeMockClient([container], makeContainerStats());
    const sampler = new ContainerStatsSampler({
      client,
      composeProject: "garazyk-e2e-test",
    });

    await sampler.sample();

    assertEquals(metrics.gauges.map((metric) => metric.name), [
      "container.cpu.percent",
      "container.memory.usage_bytes",
      "container.memory.limit_bytes",
      "container.memory.percent",
      "container.memory.rss_bytes",
      "container.memory.cache_bytes",
      "container.pids",
    ]);
    assertEquals(metrics.counters, []);
  });
});

Deno.test("telemetry: second sample emits cumulative counter deltas", async () => {
  await withTelemetryCapture(async (metrics) => {
    const container = makeContainerSummary();
    const client = makeSequencedMockClient([container], [
      makeContainerStats({
        memory_stats: {
          usage: 128000000,
          max_usage: 128000000,
          limit: 512000000,
          stats: { cache: 1, rss: 2 },
          failcnt: 1,
        },
        networks: {
          eth0: {
            rx_bytes: 100,
            rx_packets: 0,
            rx_errors: 1,
            rx_dropped: 0,
            tx_bytes: 200,
            tx_packets: 0,
            tx_errors: 2,
            tx_dropped: 0,
          },
        },
        blkio_stats: {
          io_service_bytes_recursive: [
            { major: 8, minor: 0, op: "read", value: 300 },
            { major: 8, minor: 0, op: "write", value: 400 },
          ],
        },
      }),
      makeContainerStats({
        memory_stats: {
          usage: 128000000,
          max_usage: 128000000,
          limit: 512000000,
          stats: { cache: 1, rss: 2 },
          failcnt: 4,
        },
        networks: {
          eth0: {
            rx_bytes: 150,
            rx_packets: 0,
            rx_errors: 3,
            rx_dropped: 0,
            tx_bytes: 260,
            tx_packets: 0,
            tx_errors: 5,
            tx_dropped: 0,
          },
        },
        blkio_stats: {
          io_service_bytes_recursive: [
            { major: 8, minor: 0, op: "read", value: 310 },
            { major: 8, minor: 0, op: "write", value: 425 },
          ],
        },
      }),
    ]);
    const sampler = new ContainerStatsSampler({
      client,
      composeProject: "garazyk-e2e-test",
    });

    await sampler.sample();
    await sampler.sample();

    assertEquals(metrics.counters, [
      { name: "container.memory.failcnt", value: 3 },
      { name: "container.network.rx_bytes", value: 50 },
      { name: "container.network.tx_bytes", value: 60 },
      { name: "container.network.rx_errors", value: 2 },
      { name: "container.network.tx_errors", value: 3 },
      { name: "container.blockio.read_bytes", value: 10 },
      { name: "container.blockio.write_bytes", value: 25 },
    ]);
  });
});

Deno.test("telemetry: counter reset emits no negative delta and updates baseline", async () => {
  await withTelemetryCapture(async (metrics) => {
    const container = makeContainerSummary();
    const client = makeSequencedMockClient([container], [
      makeContainerStats({
        networks: {
          eth0: {
            rx_bytes: 100,
            rx_packets: 0,
            rx_errors: 0,
            rx_dropped: 0,
            tx_bytes: 0,
            tx_packets: 0,
            tx_errors: 0,
            tx_dropped: 0,
          },
        },
      }),
      makeContainerStats({
        networks: {
          eth0: {
            rx_bytes: 20,
            rx_packets: 0,
            rx_errors: 0,
            rx_dropped: 0,
            tx_bytes: 0,
            tx_packets: 0,
            tx_errors: 0,
            tx_dropped: 0,
          },
        },
      }),
      makeContainerStats({
        networks: {
          eth0: {
            rx_bytes: 35,
            rx_packets: 0,
            rx_errors: 0,
            rx_dropped: 0,
            tx_bytes: 0,
            tx_packets: 0,
            tx_errors: 0,
            tx_dropped: 0,
          },
        },
      }),
    ]);
    const sampler = new ContainerStatsSampler({
      client,
      composeProject: "garazyk-e2e-test",
    });

    await sampler.sample();
    await sampler.sample();
    await sampler.sample();

    assertEquals(metrics.counters, [
      { name: "container.network.rx_bytes", value: 15 },
    ]);
  });
});

Deno.test("sampler: start/stop lifecycle", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats();
  const client = makeMockClient([container], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
    intervalMs: 100,
  });

  // Start should not throw
  sampler.start();
  // deno-lint-ignore no-explicit-any
  assertEquals((sampler as any).running, true);

  // Stop should not throw
  await sampler.stop();
  // deno-lint-ignore no-explicit-any
  assertEquals((sampler as any).running, false);
});

Deno.test("buildSnapshot: handles missing blkio_stats gracefully", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats({
    blkio_stats: { io_service_bytes_recursive: [] },
  });
  const client = makeMockClient([container], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
  });

  const snapshots = await sampler.sample();
  assertEquals(snapshots[0].blockioReadBytes, 0);
  assertEquals(snapshots[0].blockioWriteBytes, 0);
});

Deno.test("buildSnapshot: handles missing networks gracefully", async () => {
  const container = makeContainerSummary();
  const stats = makeContainerStats({ networks: {} });
  const client = makeMockClient([container], stats);

  const sampler = new ContainerStatsSampler({
    client,
    composeProject: "garazyk-e2e-test",
  });

  const snapshots = await sampler.sample();
  assertEquals(snapshots[0].networkRxBytes, 0);
  assertEquals(snapshots[0].networkTxBytes, 0);
});

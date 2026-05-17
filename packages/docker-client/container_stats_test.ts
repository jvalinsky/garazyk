/**
 * Tests for the ContainerStatsSampler.
 *
 * These tests use a mock DockerApiClient to verify the sampler's
 * logic without requiring a running Docker daemon.
 */

import {
  ContainerStatsSampler,
  type ContainerStatsSnapshot,
  type MemoryPressureAlert,
} from "./container_stats.ts";
import type { ContainerStats, ContainerSummary, DockerApiClient } from "./docker_api.ts";
import { assertEquals } from "@std/assert";

// ---------------------------------------------------------------------------
// Mock Docker API client
// ---------------------------------------------------------------------------

function makeMockClient(containers: ContainerSummary[], stats: ContainerStats): DockerApiClient {
  return {
    client: {} as any,
    _socketPath: "/mock",
    _available: true,
    _baseUrl: "http://localhost/v1.45",
    get available() {
      return true;
    },
    async init() {
      return true;
    },
    close() {},
    async ping() {
      return true;
    },
    async version() {
      return {} as any;
    },
    async listContainers() {
      return containers;
    },
    async inspectContainer() {
      return {} as any;
    },
    async containerLogs() {
      return new ReadableStream();
    },
    async containerStats(_id: string, _opts?: { oneShot?: boolean }) {
      return stats;
    },
    async waitContainer() {
      return { StatusCode: 0 };
    },
    async *streamEvents() {},
    async *streamContainerStats() {},
  } as unknown as DockerApiClient;
}

function makeContainerSummary(overrides: Partial<ContainerSummary> = {}): ContainerSummary {
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

function makeContainerStats(overrides: Partial<ContainerStats> = {}): ContainerStats {
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
  // Replace the client's containerStats method
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
  assertEquals((sampler as any).running, true);

  // Stop should not throw
  await sampler.stop();
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

/**
 * Tests for the Docker Engine API client.
 *
 * These are integration tests that require a running Docker daemon.
 * They are skipped if the Docker socket is not available.
 *
 * Run with: deno test -A packages/laweta/docker_api_test.ts
 */

import {
  composeProjectName,
  composeServiceName,
  type ContainerInspect,
  type ContainerSummary,
  cpuPercent,
  createDockerClient,
  DockerApiClient,
  type DockerEvent,
  findPortConflicts,
  formatMemory,
  healthStatus,
  memoryLimit,
  memoryUsage,
  parseDockerLogBuffer,
} from "./docker_api.ts";
import { assertEquals, assertExists } from "@std/assert";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let _client: DockerApiClient | null = null;

async function getClient(): Promise<DockerApiClient | null> {
  if (_client !== null) return _client;
  const client = await createDockerClient();
  _client = client;
  return client;
}

function dockerLogFrame(streamType: 1 | 2, text: string): Uint8Array {
  const payload = new TextEncoder().encode(text);
  const frame = new Uint8Array(8 + payload.length);
  frame[0] = streamType;
  frame[4] = (payload.length >>> 24) & 0xff;
  frame[5] = (payload.length >>> 16) & 0xff;
  frame[6] = (payload.length >>> 8) & 0xff;
  frame[7] = payload.length & 0xff;
  frame.set(payload, 8);
  return frame;
}

function concatBytes(...chunks: Uint8Array[]): Uint8Array {
  const output = new Uint8Array(
    chunks.reduce((total, chunk) => total + chunk.length, 0),
  );
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

interface RecordedRequest {
  pathname: string;
  search: string;
}

async function withFakeDockerApi(
  handler: (req: Request, requests: RecordedRequest[]) => Response,
  fn: (client: DockerApiClient, requests: RecordedRequest[]) => Promise<void>,
): Promise<void> {
  const requests: RecordedRequest[] = [];
  const server = Deno.serve({
    hostname: "127.0.0.1",
    port: 0,
    onListen: () => {},
  }, (req) => {
    const url = new URL(req.url);
    requests.push({ pathname: url.pathname, search: url.search });
    if (url.pathname === "/v1.43/_ping") {
      return new Response("OK");
    }
    return handler(req, requests);
  });

  const client = new DockerApiClient(
    `http://127.0.0.1:${server.addr.port}`,
  );
  try {
    assertEquals(await client.init(), true);
    requests.length = 0;
    await fn(client, requests);
  } finally {
    client.close();
    await server.shutdown();
  }
}

const minimalInspect: ContainerInspect = {
  Id: "abc123",
  Created: "",
  Name: "/abc123",
  State: {
    Status: "running",
    Running: true,
    Paused: false,
    Restarting: false,
    OOMKilled: false,
    Dead: false,
    Pid: 1,
    ExitCode: 0,
    Error: "",
    StartedAt: "",
    FinishedAt: "",
  },
  Config: {
    Image: "alpine",
    Labels: {},
    Env: [],
  },
  NetworkSettings: {
    Bridge: "",
    Ports: {},
    Networks: {},
  },
  Mounts: [],
};

const minimalStats: import("./docker_api.ts").ContainerStats = {
  read: "",
  preread: "",
  num_procs: 1,
  cpu_stats: {
    cpu_usage: {
      total_usage: 0,
      percpu_usage: [],
      usage_in_kernelmode: 0,
      usage_in_usermode: 0,
    },
    system_cpu_usage: 0,
    online_cpus: 1,
    throttling_data: { periods: 0, throttled_periods: 0, throttled_time: 0 },
  },
  precpu_stats: {
    cpu_usage: {
      total_usage: 0,
      percpu_usage: [],
      usage_in_kernelmode: 0,
      usage_in_usermode: 0,
    },
    system_cpu_usage: 0,
    online_cpus: 1,
    throttling_data: { periods: 0, throttled_periods: 0, throttled_time: 0 },
  },
  memory_stats: {
    usage: 0,
    max_usage: 0,
    limit: 0,
    stats: { cache: 0, rss: 0 },
    failcnt: 0,
  },
  blkio_stats: { io_service_bytes_recursive: [] },
  networks: {},
};

// Final test that cleans up the shared client
Deno.test(
  {
    name: "cleanup: close shared client",
    sanitizeResources: false,
    sanitizeOps: false,
  },
  () => {
    if (_client) {
      _client.close();
      _client = null;
    }
  },
);

// ---------------------------------------------------------------------------
// Client initialization
// ---------------------------------------------------------------------------

Deno.test(
  {
    name: "DockerApiClient: init and ping",
    sanitizeResources: false,
    sanitizeOps: false,
  },
  async () => {
    const client = await getClient();
    if (!client) {
      console.log("SKIP: Docker daemon not available");
      return;
    }

    assertEquals(client.available, true);
    const ping = await client.ping();
    assertEquals(ping, true);
  },
);

Deno.test("DockerApiClient: encodes container path segments", async () => {
  await withFakeDockerApi((req) => {
    const url = new URL(req.url);
    if (url.pathname.endsWith("/json")) {
      return Response.json(minimalInspect);
    }
    if (url.pathname.endsWith("/logs")) {
      return new Response("log line\n");
    }
    if (url.pathname.endsWith("/stats")) {
      return Response.json(minimalStats);
    }
    if (url.pathname.endsWith("/wait")) {
      return Response.json({ StatusCode: 0 });
    }
    return new Response("not found", { status: 404 });
  }, async (client, requests) => {
    await client.inspectContainer("project/service");
    assertEquals(
      requests.at(-1),
      { pathname: "/v1.43/containers/project%2Fservice/json", search: "" },
    );

    await client.containerLogs("name with spaces", { tail: "10" });
    assertEquals(
      requests.at(-1),
      {
        pathname: "/v1.43/containers/name%20with%20spaces/logs",
        search: "?stdout=true&stderr=true&tail=10",
      },
    );

    await client.containerStats("name?x=y", { oneShot: true });
    assertEquals(
      requests.at(-1),
      {
        pathname: "/v1.43/containers/name%3Fx%3Dy/stats",
        search: "?stream=false&one-shot=true",
      },
    );

    for await (const _stats of client.streamContainerStats("a/b")) {
      break;
    }
    assertEquals(
      requests.at(-1),
      {
        pathname: "/v1.43/containers/a%2Fb/stats",
        search: "?stream=true",
      },
    );

    await client.waitContainer("a#b");
    assertEquals(
      requests.at(-1),
      { pathname: "/v1.43/containers/a%23b/wait", search: "" },
    );

    await client.inspectContainer("abc123");
    assertEquals(
      requests.at(-1),
      { pathname: "/v1.43/containers/abc123/json", search: "" },
    );
  });
});

Deno.test("DockerApiClient: version", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  const version = await client.version();
  assertExists(version.Version);
  assertExists(version.ApiVersion);
  assertEquals(typeof version.Version, "string");
});

Deno.test("parseDockerLogBuffer: preserves multi-chunk raw TTY logs", () => {
  const raw = concatBytes(
    new TextEncoder().encode("first chunk\n"),
    new TextEncoder().encode("second chunk\n"),
  );

  assertEquals(parseDockerLogBuffer(raw), "first chunk\nsecond chunk\n");
});

Deno.test("parseDockerLogBuffer: demuxes split multiplexed frames", () => {
  const frame1 = dockerLogFrame(1, "stdout line\n");
  const frame2 = dockerLogFrame(2, "stderr line\n");
  const splitFrame2 = concatBytes(frame2.slice(0, 5), frame2.slice(5));

  assertEquals(
    parseDockerLogBuffer(concatBytes(frame1, splitFrame2)),
    "stdout line\nstderr line\n",
  );
});

// ---------------------------------------------------------------------------
// Container listing
// ---------------------------------------------------------------------------

Deno.test("DockerApiClient: listContainers", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  const containers = await client.listContainers();
  assertEquals(Array.isArray(containers), true);
  // Even if no containers are running, the response should be an array
});

Deno.test("DockerApiClient: listContainers with filters", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  const containers = await client.listContainers({ status: ["running"] });
  assertEquals(Array.isArray(containers), true);
  for (const c of containers) {
    assertEquals(c.State, "running");
  }
});

// ---------------------------------------------------------------------------
// Container inspect (requires a running container)
// ---------------------------------------------------------------------------

Deno.test("DockerApiClient: inspectContainer", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  const containers = await client.listContainers({ status: ["running"] });
  if (containers.length === 0) {
    console.log("SKIP: No running containers to inspect");
    return;
  }

  const id = containers[0].Id;
  const inspect = await client.inspectContainer(id);
  assertEquals(inspect.Id, id);
  assertExists(inspect.State);
  assertExists(inspect.State.Status);
  assertExists(inspect.Config);
});

// ---------------------------------------------------------------------------
// Container stats (requires a running container)
// ---------------------------------------------------------------------------

Deno.test("DockerApiClient: containerStats", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  const containers = await client.listContainers({ status: ["running"] });
  if (containers.length === 0) {
    console.log("SKIP: No running containers for stats");
    return;
  }

  const id = containers[0].Id;
  const stats = await client.containerStats(id);
  assertExists(stats.cpu_stats);
  assertExists(stats.memory_stats);
  assertExists(stats.cpu_stats.cpu_usage);
});

// ---------------------------------------------------------------------------
// Event streaming
// ---------------------------------------------------------------------------

Deno.test("DockerApiClient: streamEvents (basic)", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  // Start a short-lived container to generate events
  const events: DockerEvent[] = [];
  const abort = new AbortController();

  // Start event stream in background
  const eventPromise = (async () => {
    for await (
      const event of client.streamEvents({ type: ["container"] }, abort.signal)
    ) {
      events.push(event);
      if (events.length >= 3) break; // Got some events, enough to verify
    }
  })();

  // Create a container to generate events
  try {
    const proc = new Deno.Command("docker", {
      args: ["run", "--rm", "alpine", "echo", "hello-docker-api-test"],
      stdout: "piped",
      stderr: "piped",
    });
    // Don't await — let it run while we capture events
    const timeout = setTimeout(() => abort.abort(), 15000);
    await proc.output();
    clearTimeout(timeout);
  } catch {
    // alpine image may not be available — that's OK
  }

  // Give the event stream a moment to deliver
  await new Promise((resolve) => setTimeout(resolve, 1000));
  abort.abort();

  try {
    await eventPromise;
  } catch {
    // AbortError is expected
  }

  // We may or may not have captured events depending on timing,
  // but the stream mechanism should work without errors
  console.log(`  Captured ${events.length} event(s)`);
});

Deno.test("DockerApiClient: streamEvents yields final line without newline", async () => {
  await withFakeDockerApi(() =>
    new Response(
      new TextEncoder().encode(
        JSON.stringify({
          type: "container",
          action: "start",
          actor: { ID: "abc", Attributes: {} },
          scope: "local",
          time: 1,
          timeNano: 1,
        }),
      ),
    ), async (client) => {
    const events: DockerEvent[] = [];
    for await (const event of client.streamEvents()) {
      events.push(event);
    }

    assertEquals(events.length, 1);
    assertEquals(events[0].action, "start");
  });
});

Deno.test("DockerApiClient: streamEvents skips malformed NDJSON lines", async () => {
  const originalDebug = console.debug;
  const debugMessages: unknown[][] = [];
  console.debug = (...args: unknown[]) => {
    debugMessages.push(args);
  };

  try {
    await withFakeDockerApi(() =>
      new Response(
        [
          "{not-json}",
          JSON.stringify({
            type: "container",
            action: "die",
            actor: { ID: "abc", Attributes: {} },
            scope: "local",
            time: 1,
            timeNano: 1,
          }),
          "",
        ].join("\n"),
      ), async (client) => {
      const events: DockerEvent[] = [];
      for await (const event of client.streamEvents()) {
        events.push(event);
      }

      assertEquals(events.length, 1);
      assertEquals(events[0].action, "die");
      assertEquals(debugMessages.length, 1);
      assertEquals(
        String(debugMessages[0][0]).includes("DockerApiClient.streamEvents"),
        true,
      );
    });
  } finally {
    console.debug = originalDebug;
  }
});

Deno.test("DockerApiClient: streamEvents abort exits cleanly", async () => {
  await withFakeDockerApi(() =>
    new Response(
      new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("\n"));
        },
      }),
    ), async (client) => {
    const abort = new AbortController();
    const events: DockerEvent[] = [];
    const consume = (async () => {
      for await (const event of client.streamEvents(undefined, abort.signal)) {
        events.push(event);
      }
    })();

    await delay(10);
    abort.abort();
    await consume;
    assertEquals(events.length, 0);
  });
});

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

Deno.test("composeServiceName: extracts from labels", () => {
  const container: ContainerSummary = {
    Id: "abc123",
    Names: ["/my-container"],
    Image: "alpine",
    ImageID: "sha256:abc",
    Command: "echo hi",
    Created: 0,
    State: "running",
    Status: "Up 5 minutes",
    Ports: [],
    Labels: {
      "com.docker.compose.service": "my-service",
      "com.docker.compose.project": "test-project",
    },
    HostConfig: { NetworkMode: "bridge" },
    NetworkSettings: { Networks: {} },
    Mounts: [],
  };

  assertEquals(composeServiceName(container), "my-service");
  assertEquals(composeProjectName(container), "test-project");
});

Deno.test("composeServiceName: returns null when no label", () => {
  const container: ContainerSummary = {
    Id: "abc123",
    Names: ["/my-container"],
    Image: "alpine",
    ImageID: "sha256:abc",
    Command: "echo hi",
    Created: 0,
    State: "running",
    Status: "Up 5 minutes",
    Ports: [],
    Labels: {},
    HostConfig: { NetworkMode: "bridge" },
    NetworkSettings: { Networks: {} },
    Mounts: [],
  };

  assertEquals(composeServiceName(container), null);
});

Deno.test("healthStatus: returns health check status", () => {
  const container = {
    Id: "abc",
    State: {
      Status: "running",
      Running: true,
      Paused: false,
      Restarting: false,
      OOMKilled: false,
      Dead: false,
      Pid: 1,
      ExitCode: 0,
      Error: "",
      StartedAt: "",
      FinishedAt: "",
      Health: {
        Status: "healthy",
        FailingStreak: 0,
        Log: [],
      },
    },
    Config: { Image: "test", Labels: {}, Env: [] },
    NetworkSettings: { Bridge: "", Ports: {}, Networks: {} },
    Mounts: [],
    Name: "test",
    Created: "",
  } as unknown as ContainerInspect;

  assertEquals(healthStatus(container), "healthy");
});

Deno.test("healthStatus: falls back to State.Status when no health check", () => {
  const container = {
    Id: "abc",
    State: {
      Status: "running",
      Running: true,
      Paused: false,
      Restarting: false,
      OOMKilled: false,
      Dead: false,
      Pid: 1,
      ExitCode: 0,
      Error: "",
      StartedAt: "",
      FinishedAt: "",
    },
    Config: { Image: "test", Labels: {}, Env: [] },
    NetworkSettings: { Bridge: "", Ports: {}, Networks: {} },
    Mounts: [],
    Name: "test",
    Created: "",
  } as unknown as ContainerInspect;

  assertEquals(healthStatus(container), "running");
});

Deno.test("cpuPercent: computes CPU percentage", () => {
  const stats = {
    cpu_stats: {
      cpu_usage: {
        total_usage: 200_000_000,
        percpu_usage: [],
        usage_in_kernelmode: 0,
        usage_in_usermode: 0,
      },
      system_cpu_usage: 1_000_000_000,
      online_cpus: 2,
      throttling_data: { periods: 0, throttled_periods: 0, throttled_time: 0 },
    },
    precpu_stats: {
      cpu_usage: {
        total_usage: 100_000_000,
        percpu_usage: [],
        usage_in_kernelmode: 0,
        usage_in_usermode: 0,
      },
      system_cpu_usage: 500_000_000,
      online_cpus: 2,
      throttling_data: { periods: 0, throttled_periods: 0, throttled_time: 0 },
    },
    memory_stats: {
      usage: 0,
      max_usage: 0,
      limit: 0,
      stats: { cache: 0, rss: 0 },
      failcnt: 0,
    },
  } as unknown as import("./docker_api.ts").ContainerStats;

  // cpuDelta = 100M, systemDelta = 500M, cpus = 2
  // percent = (100M / 500M) * 2 * 100 = 40%
  const pct = cpuPercent(stats);
  assertEquals(pct, 40);
});

Deno.test("formatMemory: formats bytes", () => {
  const stats = {
    memory_stats: {
      usage: 128 * 1024 * 1024, // 128 MiB
      max_usage: 128 * 1024 * 1024,
      limit: 1024 * 1024 * 1024, // 1 GiB
      stats: { cache: 0, rss: 0 },
      failcnt: 0,
    },
  } as unknown as import("./docker_api.ts").ContainerStats;

  assertEquals(memoryUsage(stats), 128 * 1024 * 1024);
  assertEquals(memoryLimit(stats), 1024 * 1024 * 1024);
  const formatted = formatMemory(stats);
  assertEquals(formatted.includes("MiB"), true);
  assertEquals(formatted.includes("GiB"), true);
});

// ---------------------------------------------------------------------------
// Port conflict detection (integration test)
// ---------------------------------------------------------------------------

Deno.test("findPortConflicts: detects port conflicts from running containers", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  // Get all running containers and extract their public ports
  const containers = await client.listContainers({ status: ["running"] });
  if (containers.length === 0) {
    console.log("SKIP: No running containers to test port conflicts");
    return;
  }

  // Find a port that's actually in use
  const usedPorts = new Set<number>();
  for (const c of containers) {
    for (const p of c.Ports) {
      if (p.PublicPort) usedPorts.add(p.PublicPort);
    }
  }

  if (usedPorts.size === 0) {
    console.log("SKIP: No containers with published ports");
    return;
  }

  // Check for conflicts on the used ports
  const portList = [...usedPorts];
  const conflicts = await findPortConflicts(client, portList);
  assertEquals(conflicts.length > 0, true);
  // Each conflict should have a port in our list
  for (const conflict of conflicts) {
    assertEquals(usedPorts.has(conflict.port), true);
    assertEquals(typeof conflict.containerId, "string");
    assertEquals(conflict.containerId.length > 0, true);
  }
});

Deno.test("findPortConflicts: returns empty for unused ports", async () => {
  const client = await getClient();
  if (!client) {
    console.log("SKIP: Docker daemon not available");
    return;
  }

  // Use ports that are very unlikely to be in use
  const conflicts = await findPortConflicts(client, [59999, 59998, 59997]);
  assertEquals(conflicts.length, 0);
});

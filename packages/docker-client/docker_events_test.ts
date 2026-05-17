/**
 * Unit tests for DockerEventParser (sans-IO core).
 *
 * These tests exercise the pure synchronous event interpretation
 * and state tracking logic without requiring a Docker daemon.
 */

import { assertEquals, assertExists, assertFalse } from "jsr:@std/assert";
import { DockerEventParser } from "./docker_events.ts";
import type { ContainerSummary, DockerEvent } from "./docker_api.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeDockerEvent(overrides: Partial<DockerEvent> = {}): DockerEvent {
  return {
    type: "container",
    action: "start",
    actor: {
      ID: "abc123def456",
      Attributes: { name: "local-pds" },
    },
    scope: "local",
    time: 1700000000,
    timeNano: 1700000000_000_000_000,
    ...overrides,
  };
}

function makeContainerSummary(overrides: Partial<ContainerSummary> = {}): ContainerSummary {
  return {
    Id: "abc123def456",
    Names: ["/local-pds"],
    Image: "local-pds:latest",
    ImageID: "sha256:abc",
    Command: "/bin/sh",
    Created: 1700000000,
    State: "running",
    Status: "Up 5 minutes",
    Ports: [],
    Labels: {
      "com.docker.compose.service": "local-pds",
      "com.docker.compose.project": "garazyk",
    },
    HostConfig: { NetworkMode: "default" },
    NetworkSettings: { Networks: {} },
    Mounts: [],
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// DockerEventParser.feed()
// ---------------------------------------------------------------------------

Deno.test("DockerEventParser.feed() - start event", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({ action: "start" }));

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "started");
  if (events[0].kind === "started") {
    assertEquals(events[0].serviceName, "local-pds");
    assertEquals(events[0].containerId, "abc123def456");
  }
});

Deno.test("DockerEventParser.feed() - health_status: healthy", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({
    action: "health_status: healthy",
    actor: {
      ID: "abc123def456",
      Attributes: { name: "local-pds", healthStatus: "healthy" },
    },
  }));

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "healthy");
  if (events[0].kind === "healthy") {
    assertEquals(events[0].serviceName, "local-pds");
  }
});

Deno.test("DockerEventParser.feed() - health_status: unhealthy", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({
    action: "health_status: unhealthy",
    actor: {
      ID: "abc123def456",
      Attributes: { name: "local-pds", healthStatus: "unhealthy" },
    },
  }));

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "unhealthy");
});

Deno.test("DockerEventParser.feed() - health_status with attribute", () => {
  const parser = new DockerEventParser();
  // Docker sometimes sends action="health_status" with the status in attributes
  const events = parser.feed(makeDockerEvent({
    action: "health_status",
    actor: {
      ID: "abc123def456",
      Attributes: { name: "local-pds", healthStatus: "healthy" },
    },
  }));

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "healthy");
});

Deno.test("DockerEventParser.feed() - die event", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({
    action: "die",
    actor: {
      ID: "abc123def456",
      Attributes: { name: "local-pds", exitCode: "137", oomKill: "true" },
    },
  }));

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "died");
  if (events[0].kind === "died") {
    assertEquals(events[0].exitCode, 137);
    assertEquals(events[0].oomKilled, true);
  }
});

Deno.test("DockerEventParser.feed() - oom event", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({
    action: "oom",
    actor: {
      ID: "abc123def456",
      Attributes: { name: "local-pds" },
    },
  }));

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "oom");
  if (events[0].kind === "oom") {
    assertEquals(events[0].serviceName, "local-pds");
  }
});

Deno.test("DockerEventParser.feed() - unknown action returns empty", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({
    action: "attach",
    actor: {
      ID: "abc123def456",
      Attributes: { name: "local-pds" },
    },
  }));

  assertEquals(events.length, 0);
});

Deno.test("DockerEventParser.feed() - event with no actor ID returns empty", () => {
  const parser = new DockerEventParser();
  const events = parser.feed({
    type: "container",
    action: "start",
    actor: { ID: "", Attributes: {} },
    scope: "local",
    time: 1700000000,
    timeNano: 1700000000_000_000_000,
  });

  assertEquals(events.length, 0);
});

Deno.test("DockerEventParser.feed() - compose service name from attributes", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({
    action: "start",
    actor: {
      ID: "abc123def456",
      Attributes: { "com.docker.compose.service": "pds-db" },
    },
  }));

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "started");
  if (events[0].kind === "started") {
    assertEquals(events[0].serviceName, "pds-db");
  }
});

Deno.test("DockerEventParser.feed() - timestamp from timeNano", () => {
  const parser = new DockerEventParser();
  const events = parser.feed(makeDockerEvent({
    action: "start",
    timeNano: 1_700_000_000_500_000_000,
  }));

  assertEquals(events.length, 1);
  if (events[0].kind === "started") {
    assertEquals(events[0].timestamp, 1_700_000_000_500);
  }
});

Deno.test("DockerEventParser.feed() - timestamp from time (no timeNano)", () => {
  const parser = new DockerEventParser();
  const events = parser.feed({
    type: "container",
    action: "start",
    actor: { ID: "abc123", Attributes: { name: "test" } },
    scope: "local",
    time: 1700000000,
    timeNano: 0,
  });

  assertEquals(events.length, 1);
  if (events[0].kind === "started") {
    assertEquals(events[0].timestamp, 1700000000_000);
  }
});

// ---------------------------------------------------------------------------
// DockerEventParser state tracking
// ---------------------------------------------------------------------------

Deno.test("DockerEventParser - isHealthy after healthy event", () => {
  const parser = new DockerEventParser();
  parser.feed(makeDockerEvent({
    action: "health_status: healthy",
    actor: {
      ID: "abc123",
      Attributes: { name: "local-pds", healthStatus: "healthy" },
    },
  }));

  assertEquals(parser.isHealthy("local-pds"), true);
  assertEquals(parser.isRunning("local-pds"), false);
});

Deno.test("DockerEventParser - isRunning after start event", () => {
  const parser = new DockerEventParser();
  parser.feed(makeDockerEvent({
    action: "start",
    actor: {
      ID: "abc123",
      Attributes: { name: "local-pds" },
    },
  }));

  assertEquals(parser.isRunning("local-pds"), true);
  assertEquals(parser.isHealthy("local-pds"), false);
});

Deno.test("DockerEventParser - isExited after die event", () => {
  const parser = new DockerEventParser();
  parser.feed(makeDockerEvent({
    action: "die",
    actor: {
      ID: "abc123",
      Attributes: { name: "local-pds", exitCode: "1" },
    },
  }));

  assertEquals(parser.isExited("local-pds"), true);
  assertEquals(parser.isRunning("local-pds"), false);
  assertEquals(parser.isHealthy("local-pds"), false);
});

Deno.test("DockerEventParser - isExited after oom event", () => {
  const parser = new DockerEventParser();
  parser.feed(makeDockerEvent({
    action: "oom",
    actor: {
      ID: "abc123",
      Attributes: { name: "local-pds" },
    },
  }));

  assertEquals(parser.isExited("local-pds"), true);
});

Deno.test("DockerEventParser - state transitions", () => {
  const parser = new DockerEventParser();
  const id = "abc123";

  // Start
  parser.feed(makeDockerEvent({
    action: "start",
    actor: { ID: id, Attributes: { name: "svc" } },
  }));
  assertEquals(parser.isRunning("svc"), true);
  assertEquals(parser.isHealthy("svc"), false);

  // Healthy
  parser.feed(makeDockerEvent({
    action: "health_status: healthy",
    actor: { ID: id, Attributes: { name: "svc", healthStatus: "healthy" } },
  }));
  assertEquals(parser.isHealthy("svc"), true);
  assertEquals(parser.isRunning("svc"), false); // "healthy" != "running"

  // Unhealthy
  parser.feed(makeDockerEvent({
    action: "health_status: unhealthy",
    actor: { ID: id, Attributes: { name: "svc", healthStatus: "unhealthy" } },
  }));
  assertEquals(parser.isHealthy("svc"), false);
  assertEquals(parser.isExited("svc"), false);

  // Die
  parser.feed(makeDockerEvent({
    action: "die",
    actor: { ID: id, Attributes: { name: "svc", exitCode: "0" } },
  }));
  assertEquals(parser.isExited("svc"), true);
});

Deno.test("DockerEventParser - getContainerId", () => {
  const parser = new DockerEventParser();
  parser.feed(makeDockerEvent({
    action: "start",
    actor: { ID: "abc123", Attributes: { name: "svc" } },
  }));

  assertEquals(parser.getContainerId("svc"), "abc123");
  assertEquals(parser.getContainerId("unknown"), undefined);
});

Deno.test("DockerEventParser - getContainerState", () => {
  const parser = new DockerEventParser();
  parser.feed(makeDockerEvent({
    action: "die",
    actor: {
      ID: "abc123",
      Attributes: { name: "svc", exitCode: "137", oomKill: "true" },
    },
  }));

  const state = parser.getContainerState("abc123");
  assertExists(state);
  assertEquals(state.status, "exited");
  assertEquals(state.exitCode, 137);
  assertEquals(state.oomKilled, true);
});

// ---------------------------------------------------------------------------
// DockerEventParser.loadContainers()
// ---------------------------------------------------------------------------

Deno.test("DockerEventParser.loadContainers() - populates name mapping", () => {
  const parser = new DockerEventParser();
  parser.loadContainers([
    makeContainerSummary({
      Id: "abc123",
      Names: ["/local-pds"],
      Labels: { "com.docker.compose.service": "local-pds" },
    }),
    makeContainerSummary({
      Id: "def456",
      Names: ["/pds-db"],
      Labels: { "com.docker.compose.service": "pds-db" },
    }),
  ]);

  assertEquals(parser.getContainerId("local-pds"), "abc123");
  assertEquals(parser.getContainerId("pds-db"), "def456");
});

Deno.test("DockerEventParser.loadContainer() - indexes by container name", () => {
  const parser = new DockerEventParser();
  parser.loadContainer(makeContainerSummary({
    Id: "abc123",
    Names: ["/my-container-name"],
    Labels: { "com.docker.compose.service": "local-pds" },
  }));

  // Both compose service name and container name should resolve
  assertEquals(parser.getContainerId("local-pds"), "abc123");
  assertEquals(parser.getContainerId("my-container-name"), "abc123");
});

Deno.test("DockerEventParser.loadContainers() - no compose label", () => {
  const parser = new DockerEventParser();
  parser.loadContainer(makeContainerSummary({
    Id: "abc123",
    Names: ["/standalone-container"],
    Labels: {},
  }));

  // Should still index by container name
  assertEquals(parser.getContainerId("standalone-container"), "abc123");
});

// ---------------------------------------------------------------------------
// DockerEventParser - unknown health status
// ---------------------------------------------------------------------------

Deno.test("DockerEventParser.feed() - health_status with unknown status", () => {
  const parser = new DockerEventParser();
  // Docker sometimes sends health_status without a clear status
  const events = parser.feed(makeDockerEvent({
    action: "health_status",
    actor: {
      ID: "abc123",
      Attributes: { name: "local-pds" },
    },
  }));

  // No WatcherEvent emitted for unknown status
  assertEquals(events.length, 0);

  // But the state should still be tracked
  const state = parser.getContainerState("abc123");
  assertExists(state);
  assertEquals(state.status, "unknown");
});

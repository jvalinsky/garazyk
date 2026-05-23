import { assertEquals } from "@std/assert";
import {
  allocateHostPorts,
  cleanupStalePortLeases,
  parsePortRange,
  releaseRunPortLeases,
} from "./port_allocator.ts";

Deno.test("parsePortRange validates START:END values", () => {
  assertEquals(parsePortRange("30000:30010"), { start: 30000, end: 30010 });
});

Deno.test("allocateHostPorts returns unique leases and releases them by run id", async () => {
  const leaseDir = await Deno.makeTempDir({ prefix: "garazyk-port-leases-" });
  try {
    const leases = await allocateHostPorts({
      runId: "run-a",
      resources: ["pds", "appview", "beskid"],
      leaseDir,
      range: { start: 43000, end: 43100 },
    });
    const ports = Object.values(leases).map((lease) => lease.port);
    assertEquals(new Set(ports).size, 3);

    await releaseRunPortLeases("run-a", leaseDir);
    const remaining = [];
    for await (const entry of Deno.readDir(leaseDir)) {
      remaining.push(entry.name);
    }
    assertEquals(remaining, []);
  } finally {
    await Deno.remove(leaseDir, { recursive: true });
  }
});

Deno.test("cleanupStalePortLeases removes dead-owner leases", async () => {
  const leaseDir = await Deno.makeTempDir({ prefix: "garazyk-port-leases-" });
  const leasePath = `${leaseDir}/43001.json`;
  try {
    await Deno.writeTextFile(
      leasePath,
      JSON.stringify({
        runId: "stale",
        resource: "pds",
        port: 43001,
        ownerPid: 99999999,
        createdAt: new Date().toISOString(),
      }),
    );
    await cleanupStalePortLeases(leaseDir);
    const remaining = [];
    for await (const entry of Deno.readDir(leaseDir)) {
      remaining.push(entry.name);
    }
    assertEquals(remaining, []);
  } finally {
    await Deno.remove(leaseDir, { recursive: true });
  }
});

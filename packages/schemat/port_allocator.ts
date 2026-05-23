/** Cross-process host port lease helpers for local test isolation. @module port_allocator */

import { join } from "@std/path";

/** Inclusive TCP port range. */
export interface PortRange {
  /** Lowest allocatable port. */
  start: number;
  /** Highest allocatable port. */
  end: number;
}

/** A held host-port lease. */
export interface HostPortLease {
  /** Logical resource key. */
  resource: string;
  /** Allocated port. */
  port: number;
  /** Lease file path. */
  leaseFile: string;
}

/** Options for host-port allocation. */
export interface HostPortAllocationOptions {
  /** Owning run id. */
  runId: string;
  /** Logical resource key. */
  resource: string;
  /** Port range. Defaults to ATPROTO_PORT_RANGE or 20000:60999. */
  range?: PortRange;
  /** Directory where lease files are stored. */
  leaseDir?: string;
  /** Owning process id. Defaults to Deno.pid. */
  ownerPid?: number;
  /** Bind host used for availability checks. */
  hostname?: string;
  /** Maximum candidate attempts. */
  attempts?: number;
}

interface LeaseRecord {
  runId: string;
  resource: string;
  port: number;
  ownerPid: number;
  createdAt: string;
}

/** Parse a START:END port range string. */
export function parsePortRange(
  value: string | undefined,
): PortRange | undefined {
  if (!value) return undefined;
  const match = value.match(/^(\d+):(\d+)$/);
  if (!match) {
    throw new Error(`Invalid port range "${value}" (expected START:END)`);
  }
  const start = Number.parseInt(match[1], 10);
  const end = Number.parseInt(match[2], 10);
  if (
    !Number.isInteger(start) || !Number.isInteger(end) || start < 1 ||
    end > 65535 || start > end
  ) {
    throw new Error(`Invalid port range "${value}"`);
  }
  return { start, end };
}

/** Return the default lease directory. */
export function defaultPortLeaseDir(): string {
  const tmp = Deno.env.get("TMPDIR") || "/tmp";
  return join(tmp, "garazyk-resource-leases");
}

/** Allocate one host port and create a process-safe lease file. */
export async function allocateHostPort(
  options: HostPortAllocationOptions,
): Promise<HostPortLease> {
  const range = options.range ??
    parsePortRange(Deno.env.get("ATPROTO_PORT_RANGE")) ??
    { start: 20000, end: 60999 };
  const leaseDir = options.leaseDir ?? defaultPortLeaseDir();
  const ownerPid = options.ownerPid ?? Deno.pid;
  const hostname = options.hostname ?? "127.0.0.1";
  const attempts = options.attempts ?? 1000;
  await Deno.mkdir(leaseDir, { recursive: true });
  await cleanupStalePortLeases(leaseDir);

  for (let i = 0; i < attempts; i++) {
    const port = randomPort(range);
    const leaseFile = join(leaseDir, `${port}.json`);
    let file: Deno.FsFile | undefined;
    try {
      file = await Deno.open(leaseFile, {
        createNew: true,
        write: true,
      });
    } catch (exc) {
      if (exc instanceof Deno.errors.AlreadyExists) continue;
      throw exc;
    }

    const record: LeaseRecord = {
      runId: options.runId,
      resource: options.resource,
      port,
      ownerPid,
      createdAt: new Date().toISOString(),
    };

    try {
      const listener = Deno.listen({ hostname, port });
      listener.close();
      await file.write(
        new TextEncoder().encode(JSON.stringify(record, null, 2) + "\n"),
      );
      file.close();
      return { resource: options.resource, port, leaseFile };
    } catch {
      try {
        file.close();
      } catch {
        // Best effort.
      }
      await Deno.remove(leaseFile).catch(() => undefined);
    }
  }

  throw new Error(
    `Unable to allocate a free host port for ${options.resource} in ${range.start}:${range.end}`,
  );
}

/** Allocate ports for a set of logical resources. */
export async function allocateHostPorts(
  options: Omit<HostPortAllocationOptions, "resource"> & {
    resources: string[];
  },
): Promise<Record<string, HostPortLease>> {
  const leases: Record<string, HostPortLease> = {};
  try {
    for (const resource of options.resources) {
      leases[resource] = await allocateHostPort({ ...options, resource });
    }
    return leases;
  } catch (exc) {
    await releaseRunPortLeases(options.runId, options.leaseDir);
    throw exc;
  }
}

/** Release all port leases owned by a run id. */
export async function releaseRunPortLeases(
  runId: string,
  leaseDir = defaultPortLeaseDir(),
): Promise<void> {
  try {
    for await (const entry of Deno.readDir(leaseDir)) {
      if (!entry.isFile || !entry.name.endsWith(".json")) continue;
      const path = join(leaseDir, entry.name);
      const record = await readLease(path);
      if (record?.runId === runId) {
        await Deno.remove(path).catch(() => undefined);
      }
    }
  } catch (exc) {
    if (!(exc instanceof Deno.errors.NotFound)) throw exc;
  }
}

/** Remove leases whose owner process is no longer alive. */
export async function cleanupStalePortLeases(
  leaseDir = defaultPortLeaseDir(),
): Promise<void> {
  try {
    for await (const entry of Deno.readDir(leaseDir)) {
      if (!entry.isFile || !entry.name.endsWith(".json")) continue;
      const path = join(leaseDir, entry.name);
      const record = await readLease(path);
      if (!record || !processIsAlive(record.ownerPid)) {
        await Deno.remove(path).catch(() => undefined);
      }
    }
  } catch (exc) {
    if (!(exc instanceof Deno.errors.NotFound)) throw exc;
  }
}

/** Build a loopback HTTP URL for an allocated port. */
export function hostUrlForPort(port: number): string {
  return `http://127.0.0.1:${port}`;
}

async function readLease(path: string): Promise<LeaseRecord | undefined> {
  try {
    return JSON.parse(await Deno.readTextFile(path)) as LeaseRecord;
  } catch {
    return undefined;
  }
}

function processIsAlive(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    Deno.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function randomPort(range: PortRange): number {
  const span = range.end - range.start + 1;
  return range.start + Math.floor(Math.random() * span);
}

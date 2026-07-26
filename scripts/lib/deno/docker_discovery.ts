/**
 * @module lib/deno/docker_discovery
 *
 * Docker container discovery helpers for e2e scenarios.
 *
 * These utilities harden container discovery against multi-stack ambiguity:
 * instead of picking the first container matching a glob (e.g.
 * `*local-relay-1*`), they derive the compose project prefix from the
 * PDS container's `com.docker.compose.project` label, then use that
 * project-scoped prefix to find the matching relay or other service
 * containers. This ensures two concurrent e2e stacks cannot select
 * the wrong relay.
 *
 * Usage:
 * ```typescript
 * import { discoverPdsContainer, discoverRelayContainer }
 *   from "../../lib/deno/docker_discovery.ts";
 *
 * const pdsContainer = await discoverPdsContainer();
 * const relayContainer = await discoverRelayContainer(pdsContainer);
 * ```
 */

/** Result of running `docker ps --filter` */
interface ContainerInfo {
  id: string;
  name: string;
  labels: Record<string, string>;
}

/**
 * Run a shell command and return its stdout as a trimmed string.
 * Throws on non-zero exit.
 */
async function runCmd(
  cmd: string[],
  timeoutMs = 15_000,
): Promise<string> {
  const abortController = new AbortController();
  const timer = setTimeout(() => abortController.abort(), timeoutMs);
  try {
    const proc = new Deno.Command(cmd[0], {
      args: cmd.slice(1),
      stdout: "piped",
      stderr: "piped",
      signal: abortController.signal,
    });
    const { code, stdout, stderr } = await proc.output();
    if (code !== 0) {
      const err = new TextDecoder().decode(stderr).trim();
      throw new Error(
        `Command "${cmd.join(" ")}" failed (exit ${code}): ${err}`,
      );
    }
    return new TextDecoder().decode(stdout).trim();
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Parse `docker ps --format '{{json .}}'` output into structured info.
 * Each line is a JSON object with ID, Names, Labels, etc.
 */
function parseDockerPsLines(
  output: string,
): ContainerInfo[] {
  if (!output) return [];
  const lines = output.split("\n").filter((l) => l.trim().length > 0);
  return lines.map((line) => {
    const raw = JSON.parse(line);
    const labelsRaw = raw.Labels as string;
    const labels: Record<string, string> = {};
    if (labelsRaw) {
      // Docker --format {{json .Labels}} emits a JSON object string
      try {
        Object.assign(labels, JSON.parse(labelsRaw));
      } catch {
        // Labels might be a comma-separated string in older Docker versions;
        // skip parsing.
      }
    }
    // Names field may be a string with leading / or an array on some Docker versions
    const rawNames = raw.Names;
    if (!rawNames) {
      return { id: raw.ID || "", name: "", labels };
    }
    const name = Array.isArray(rawNames) ? rawNames[0] : rawNames;
    return {
      id: raw.ID || "",
      name: typeof name === "string" ? name.replace(/^\/+/, "") : "",
      labels,
    };
  });
}

/**
 * Discover the PDS container by matching the service name pattern.
 * Looks for a container whose name matches `*pds*` or has the label
 * `com.docker.compose.service` set to a value containing "pds".
 *
 * Returns the container name (usable with `docker exec`).
 *
 * @throws If no PDS container is found or multiple ambiguous matches exist.
 */
export async function discoverPdsContainer(): Promise<string> {
  const output = await runCmd([
    "docker", "ps",
    "--format", "{{json .}}",
    "--no-trunc",
  ]);

  const containers = parseDockerPsLines(output);

  const pdsContainers = containers.filter((c) => {
    // Match by name
    const nameLower = c.name.toLowerCase();
    if (nameLower.includes("pds") && !nameLower.includes("appview")) {
      return true;
    }
    // Match by compose service label
    const service = (c.labels["com.docker.compose.service"] || "").toLowerCase();
    if (service.includes("pds") && !service.includes("appview")) {
      return true;
    }
    return false;
  });

  if (pdsContainers.length === 0) {
    throw new Error(
      "No PDS container found. Ensure a PDS is running via docker compose.",
    );
  }
  if (pdsContainers.length > 1) {
    // Prefer the one with a compose project label (more likely to be our target)
    const labelled = pdsContainers.filter(
      (c) => c.labels["com.docker.compose.project"],
    );
    if (labelled.length === 1) return labelled[0].name;
    throw new Error(
      `Multiple PDS containers found: ${
        pdsContainers.map((c) => c.name).join(", ")
      }. Use PDS_CONTAINER env var to disambiguate.`,
    );
  }

  return pdsContainers[0].name;
}

/**
 * Extract the compose project prefix from a PDS container.
 *
 * Docker Compose labels containers with `com.docker.compose.project`.
 * The project prefix is this value. If absent, derives it by stripping
 * the trailing `-pds-1` or `-pds-1` from the container name.
 *
 * @param pdsContainerName - The PDS container name (e.g. `garazyk-e2e-pds-1`)
 * @returns The compose project prefix (e.g. `garazyk-e2e`)
 */
export async function getComposeProjectPrefix(
  pdsContainerName: string,
): Promise<string> {
  // First, try to get the compose project label from the container
  try {
    const inspect = await runCmd([
      "docker", "inspect",
      pdsContainerName,
      "--format", "{{index .Config.Labels \"com.docker.compose.project\"}}",
    ]);
    if (inspect && inspect.length > 0 && inspect !== "<no value>") {
      return inspect;
    }
  } catch {
    // Fall through to name-based derivation
  }

  // Derive from container name: strip the trailing `-pds-1` or `-1` suffix
  // Container names from docker compose follow: <project>-<service>-<replica>
  // e.g. garazyk-e2e-pds-1 → project is garazyk-e2e
  const name = pdsContainerName.replace(/^\/+/, ""); // strip leading /
  const pdsSuffixMatch = name.match(/^(.*?)-pds-\d+$/);
  if (pdsSuffixMatch) {
    return pdsSuffixMatch[1];
  }
  // Try generic suffix: just strip the last `-<n>` segment
  const genericSuffixMatch = name.match(/^(.*)-\d+$/);
  if (genericSuffixMatch) {
    return genericSuffixMatch[1];
  }

  throw new Error(
    `Cannot derive compose project prefix from container name: ${pdsContainerName}`,
  );
}

/**
 * Discover the relay container for the same compose project as the PDS.
 * Uses the PDS-anchored discovery pattern to avoid multi-stack ambiguity.
 *
 * @param pdsContainerName - The PDS container name (from {@link discoverPdsContainer})
 * @param serviceLabel - The relay compose service label to match (default: "relay")
 * @returns The relay container name (usable with `docker exec`)
 *
 * @throws If no relay container is found for the PDS's compose project.
 */
export async function discoverRelayContainer(
  pdsContainerName: string,
  serviceLabel = "relay",
): Promise<string> {
  const projectPrefix = await getComposeProjectPrefix(pdsContainerName);

  // List containers for the same compose project
  const output = await runCmd([
    "docker", "ps",
    "--format", "{{json .}}",
    "--no-trunc",
    "--filter", `label=com.docker.compose.project=${projectPrefix}`,
  ]);

  const containers = parseDockerPsLines(output);

  // Find relay containers within this project
  const relayContainers = containers.filter((c) => {
    const nameLower = c.name.toLowerCase();
    const service = (c.labels["com.docker.compose.service"] || "").toLowerCase();

    // Match by compose service label
    if (service === serviceLabel) return true;
    if (service.includes(serviceLabel)) return true;

    // Match by name pattern
    if (nameLower.includes(serviceLabel)) return true;

    return false;
  });

  if (relayContainers.length === 0) {
    throw new Error(
      `No relay container found for compose project "${projectPrefix}". ` +
      `Searched for service label matching "${serviceLabel}".`,
    );
  }
  if (relayContainers.length > 1) {
    throw new Error(
      `Multiple relay containers found in project "${projectPrefix}": ` +
      relayContainers.map((c) => c.name).join(", "),
    );
  }

  return relayContainers[0].name;
}

/**
 * Resolve a container name from a service pattern, scoped to the
 * same compose project as the PDS. Useful for finding arbitrary
 * service containers (mock-twilio, plc, etc.).
 *
 * @param pdsContainerName - The PDS container name
 * @param servicePattern - Service name substring to match (e.g. "mock-twilio", "plc")
 * @returns The container name, or null if not found
 */
export async function discoverServiceContainer(
  pdsContainerName: string,
  servicePattern: string,
): Promise<string | null> {
  const projectPrefix = await getComposeProjectPrefix(pdsContainerName);

  const output = await runCmd([
    "docker", "ps",
    "--format", "{{json .}}",
    "--no-trunc",
    "--filter", `label=com.docker.compose.project=${projectPrefix}`,
  ]);

  const containers = parseDockerPsLines(output);

  const matches = containers.filter((c) => {
    const nameLower = c.name.toLowerCase();
    const service = (c.labels["com.docker.compose.service"] || "").toLowerCase();
    if (service === servicePattern) return true;
    if (nameLower.includes(servicePattern)) return true;
    return false;
  });

  if (matches.length === 0) return null;
  if (matches.length > 1) {
    // Prefer exact service label match
    const exact = matches.filter(
      (c) => (c.labels["com.docker.compose.service"] || "").toLowerCase() === servicePattern,
    );
    if (exact.length === 1) return exact[0].name;
  }
  return matches[0].name;
}

/**
 * Run a command inside a Docker container.
 *
 * @param containerName - Container to execute in
 * @param cmd - Command and arguments to run
 * @param timeoutMs - Timeout in milliseconds
 * @returns stdout of the command
 */
export async function dockerExec(
  containerName: string,
  cmd: string[],
  timeoutMs = 15_000,
): Promise<string> {
  return await runCmd(
    ["docker", "exec", containerName, ...cmd],
    timeoutMs,
  );
}

/**
 * Run a Docker CLI command (on the host, not inside a container).
 *
 * Useful for `docker inspect`, `docker ps`, `docker network`, etc.
 *
 * @param args - Docker CLI arguments (e.g. `["inspect", "pds-1", "--format", "..."]`)
 * @param timeoutMs - Timeout in milliseconds
 * @returns stdout of the command
 */
export async function dockerCli(
  args: string[],
  timeoutMs = 15_000,
): Promise<string> {
  return await runCmd(["docker", ...args], timeoutMs);
}

/**
 * Disconnect a container from a Docker network by name.
 *
 * @param containerName - Container to disconnect
 * @param networkName - Docker network name
 */
export async function disconnectFromNetwork(
  containerName: string,
  networkName: string,
): Promise<void> {
  await runCmd([
    "docker", "network", "disconnect",
    networkName,
    containerName,
  ]);
}

/**
 * Reconnect a container to a Docker network by name.
 *
 * @param containerName - Container to reconnect
 * @param networkName - Docker network name
 */
export async function reconnectToNetwork(
  containerName: string,
  networkName: string,
): Promise<void> {
  await runCmd([
    "docker", "network", "connect",
    networkName,
    containerName,
  ]);
}

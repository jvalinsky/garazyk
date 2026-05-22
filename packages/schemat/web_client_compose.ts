/**
 * Web client Docker Compose rendering for AT Protocol topologies.
 *
 * Generates docker-compose YAML overlays for web client services,
 * including source build Dockerfiles, git clone orchestration,
 * and network alias configuration.
 *
 * @module schemat/web-client-compose
 */

import { dirname, join } from "@std/path";
import type { WebClientTopology } from "./topology.ts";
import { TopologyRegistry } from "./topology_presets.ts";

/** Options for rendering a web client compose overlay. */
export interface WebClientComposeOptions {
  /** Path to write the compose file. */
  output: string;
  /** Directory for runtime artifacts (build contexts, diagnostics). */
  runDir: string;
  /** Root of the Garazyk checkout. */
  repoRoot: string;
  /** Whether to allow hybrid (public internet) network access. */
  allowHybrid: boolean;
  /** Docker network name. */
  network: string;
}

function q(value: string): string {
  return JSON.stringify(value);
}

function yamlMap(values: Record<string, string>, indent: string): string {
  return Object.entries(values)
    .map(([key, value]) => `${indent}${key}: ${q(value)}`)
    .join("\n");
}

async function runGit(args: string[], cwd?: string): Promise<void> {
  const command = new Deno.Command("git", {
    args,
    cwd,
    stdout: "inherit",
    stderr: "inherit",
  });
  const { code } = await command.output();
  if (code !== 0) {
    throw new Error(`git ${args.join(" ")} failed with exit code ${code}`);
  }
}

/**
 * Prepare a git clone context for building a web client from source.
 *
 * Clones the client source repository (with caching), fetches the
 * requested ref, and checks out the source tree.
 *
 * @param client - Web client topology preset
 * @param buildDir - Directory for the build context
 */
export async function prepareSourceBuildContext(
  client: WebClientTopology,
  buildDir: string,
): Promise<void> {
  const safeName = client.name.replace(/[^A-Za-z0-9_.-]+/g, "-").toLowerCase();
  const cacheDir = join("/tmp/garazyk-atproto-e2e/cache", safeName);
  const sourceDir = join(buildDir, "source");

  try {
    await Deno.stat(join(cacheDir, ".git"));
  } catch {
    await Deno.mkdir(dirname(cacheDir), { recursive: true });
    await runGit(["clone", client.source, cacheDir]);
  }

  await runGit(["fetch", "--tags", "--force", "origin", client.ref], cacheDir);
  try {
    await Deno.remove(sourceDir, { recursive: true });
  } catch {
    // Missing source checkout is fine; it is recreated below.
  }
  await runGit(["clone", cacheDir, sourceDir]);
  await runGit(["checkout", client.ref], sourceDir);
}

/**
 * Write a Dockerfile for building a web client from source.
 *
 * Validates that the client ref is pinned (commit hash or tag) unless
 * `ATPROTO_ALLOW_UNPINNED_WEB_CLIENT` is set. Generates a Dockerfile
 * that installs dependencies and runs the client's serve command.
 *
 * @param client - Web client topology preset
 * @param runDir - Runtime directory for the build context
 * @returns The build directory path containing the Dockerfile
 * @throws If the client ref is not pinned and unpinned refs are not allowed
 */
export async function writeSourceDockerfile(
  client: WebClientTopology,
  runDir: string,
): Promise<string> {
  const allowUnpinned =
    Deno.env.get("ATPROTO_ALLOW_UNPINNED_WEB_CLIENT") === "1";
  const looksPinned = /^[0-9a-f]{12,40}$/i.test(client.ref) ||
    /^refs\/tags\//.test(client.ref) ||
    /^v?\d+\.\d+\.\d+/.test(client.ref);
  if (!allowUnpinned && !looksPinned) {
    throw new Error(
      `${client.name} uses ref=${client.ref}. Set the preset ref env var to a pinned commit/tag, or set ATPROTO_ALLOW_UNPINNED_WEB_CLIENT=1 for local exploration.`,
    );
  }

  const buildDir = join(runDir, "web-client-build");
  await Deno.mkdir(buildDir, { recursive: true });
  await prepareSourceBuildContext(client, buildDir);
  const dockerfile = join(buildDir, "Dockerfile");
  const installCommand =
    client.buildPreset === "social-app" || client.buildPreset === "witchsky"
      ? "corepack enable && yarn install --immutable || yarn install"
      : "npm ci || npm install";
  const commandJson = JSON.stringify(client.serveCommand);
  await Deno.writeTextFile(
    dockerfile,
    `FROM node:20-bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY source /src/app
WORKDIR /src/app
RUN ${installCommand}
EXPOSE 2590
CMD ${commandJson}
`,
  );
  return buildDir;
}

/**
 * Render a docker-compose YAML overlay for a web client service.
 *
 * Generates a complete compose file that adds a web client service
 * (either built from source or using the local garazyk-ui image),
 * a browser runner service, and network alias configuration for
 * DNS interception.
 *
 * @param presetName - Name of the web client preset (must exist in `WEB_CLIENT_PRESETS`)
 * @param options - Rendering options
 * @returns The rendered docker-compose YAML string
 * @throws If the preset name is not found in `WEB_CLIENT_PRESETS`
 */
export async function renderWebClientCompose(
  presetName: string,
  options: WebClientComposeOptions,
): Promise<string> {
  const client = TopologyRegistry.getWebClient(presetName);
  if (!client) {
    throw new Error(`Unknown web-client preset ${presetName}`);
  }

  const dnsAliases = [
    "bsky.app",
    "api.bsky.app",
    "public.api.bsky.app",
  ];
  const plcAliases = ["plc.directory"];
  const relayAliases = ["bsky.network"];
  const appviewNetwork = [
    "        aliases:",
    ...dnsAliases.map((alias) => `          - ${alias}`),
  ].join("\n");

  let webClientService: string;
  if (client.buildPreset === "garazyk-ui") {
    webClientService = `  web-client:
    build:
      context: ${q(join(options.repoRoot, "docker/local-network"))}
      dockerfile: Dockerfile.local
    entrypoint: ["/usr/local/bin/garazyk-ui"]
    command: ["serve", "--port", "2590"]
    ports:
      - "2591:2590"
    environment:
${yamlMap(client.env, "      ")}
    depends_on:
      local-pds:
        condition: service_healthy
      local-appview:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:2590/lab"]
      interval: ${client.healthCheck.intervalSeconds}s
      timeout: ${client.healthCheck.timeoutSeconds}s
      retries: ${client.healthCheck.retries}
      start_period: ${client.healthCheck.startPeriodSeconds}s
    networks:
      - ${options.network}`;
  } else {
    const buildContext = await writeSourceDockerfile(client, options.runDir);
    webClientService = `  web-client:
    build:
      context: ${q(buildContext)}
    ports:
      - "2591:2590"
    environment:
${yamlMap(client.env, "      ")}
    depends_on:
      local-pds:
        condition: service_healthy
      local-appview:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:2590/"]
      interval: ${client.healthCheck.intervalSeconds}s
      timeout: ${client.healthCheck.timeoutSeconds}s
      retries: ${client.healthCheck.retries}
      start_period: ${client.healthCheck.startPeriodSeconds}s
    networks:
      - ${options.network}`;
  }

  const blockedHosts = options.allowHybrid || client.allowHybridNetwork
    ? []
    : ["bsky.app", "api.bsky.app", "bsky.network", "plc.directory"];

  return `services:
  local-appview:
    networks:
      ${options.network}:
${appviewNetwork}

  local-plc:
    networks:
      ${options.network}:
        aliases:
${plcAliases.map((alias) => `          - ${alias}`).join("\n")}

  local-relay:
    networks:
      ${options.network}:
        aliases:
${relayAliases.map((alias) => `          - ${alias}`).join("\n")}

${webClientService}

  browser-runner:
    image: mcr.microsoft.com/playwright:v1.44.1-jammy
    profiles: ["browser"]
    working_dir: /workspace
    environment:
      WEB_CLIENT_URL: ${q(client.internalUrl)}
      WEB_CLIENT_PUBLIC_URL: ${q(client.publicUrl)}
      OAUTH_CLIENT_URL: ${q(client.internalUrl)}
      PDS_URL: "http://local-pds:2583"
      PLC_URL: "http://local-plc:2582"
      APPVIEW_URL: "http://local-appview:3200"
      ATPROTO_BLOCKED_PUBLIC_HOSTS: ${q(blockedHosts.join(","))}
    volumes:
      - ${q(`${options.repoRoot}:/workspace:ro`)}
      - ${q(`${join(options.runDir, "diagnostics")}:/diagnostics`)}
    depends_on:
      web-client:
        condition: service_healthy
    networks:
      - ${options.network}

networks:
  ${options.network}:
    external: false
`;
}

export async function main() {
  const args = Deno.args;
  if (args.length === 0 || args.includes("--help")) {
    console.log(
      `Usage: deno run -A packages/schemat/web_client_compose.ts <preset> <output-file> [options]`,
    );
    Deno.exit(0);
  }

  const [preset, output] = args;
  const repoRoot = Deno.cwd();
  const runDir = Deno.env.get("ATPROTO_RUN_DIR") || join(repoRoot, ".run");

  const yaml = await renderWebClientCompose(preset, {
    output,
    runDir,
    repoRoot,
    allowHybrid: Deno.env.get("ATPROTO_ALLOW_HYBRID_WEB_CLIENT") === "1",
    network: Deno.env.get("ATPROTO_DOCKER_NETWORK") || "atproto-local-net",
  });

  await Deno.writeTextFile(output, yaml);
  console.log(`Wrote web client compose to ${output}`);
}

if (import.meta.main) {
  await main();
}

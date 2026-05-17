#!/usr/bin/env -S deno run -A
import { dirname, join } from "@std/path";
import { WEB_CLIENT_PRESETS, WebClientTopology } from "@garazyk/schemat";

interface Args {
  preset: string;
  output: string;
  runDir: string;
  repoRoot: string;
  allowHybrid: boolean;
  network: string;
}

function usage(): never {
  console.error(
    "Usage: render_web_client_compose.ts --preset NAME --output FILE --run-dir DIR --repo-root DIR [--allow-hybrid] [--network NAME]",
  );
  Deno.exit(2);
}

function parseArgs(argv: string[]): Args {
  const args: Partial<Args> = { allowHybrid: false, network: "local_net" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--allow-hybrid") {
      args.allowHybrid = true;
      continue;
    }
    if (
      arg === "--preset" || arg === "--output" || arg === "--run-dir" ||
      arg === "--repo-root" || arg === "--network"
    ) {
      const value = argv[++i];
      if (!value) usage();
      if (arg === "--preset") args.preset = value;
      if (arg === "--output") args.output = value;
      if (arg === "--run-dir") args.runDir = value;
      if (arg === "--repo-root") args.repoRoot = value;
      if (arg === "--network") args.network = value;
      continue;
    }
    usage();
  }
  if (!args.preset || !args.output || !args.runDir || !args.repoRoot) usage();
  return args as Args;
}

function q(value: string): string {
  return JSON.stringify(value);
}

function yamlMap(values: Record<string, string>, indent: string): string {
  return Object.entries(values)
    .map(([key, value]) => `${indent}${key}: ${q(value)}`)
    .join("\n");
}

async function runGit(args: string[], cwd?: string) {
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

async function prepareSourceBuildContext(
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

async function writeSourceDockerfile(client: WebClientTopology, runDir: string): Promise<string> {
  const allowUnpinned = Deno.env.get("ATPROTO_ALLOW_UNPINNED_WEB_CLIENT") === "1";
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
  const installCommand = client.buildPreset === "social-app" || client.buildPreset === "witchsky"
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

async function render(args: Args): Promise<string> {
  const client = WEB_CLIENT_PRESETS[args.preset];
  if (!client) {
    throw new Error(`Unknown web-client preset ${args.preset}`);
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
      context: ${q(join(args.repoRoot, "docker/local-network"))}
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
      - ${args.network}`;
  } else {
    const buildContext = await writeSourceDockerfile(client, args.runDir);
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
      - ${args.network}`;
  }

  const blockedHosts = args.allowHybrid || client.allowHybridNetwork
    ? []
    : ["bsky.app", "api.bsky.app", "bsky.network", "plc.directory"];

  return `services:
  local-appview:
    networks:
      ${args.network}:
${appviewNetwork}

  local-plc:
    networks:
      ${args.network}:
        aliases:
${plcAliases.map((alias) => `          - ${alias}`).join("\n")}

  local-relay:
    networks:
      ${args.network}:
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
      - ${q(`${args.repoRoot}:/workspace:ro`)}
      - ${q(`${join(args.runDir, "diagnostics")}:/diagnostics`)}
    depends_on:
      web-client:
        condition: service_healthy
    networks:
      - ${args.network}

networks:
  ${args.network}:
    external: false
`;
}

if (import.meta.main) {
  const args = parseArgs(Deno.args);
  await Deno.mkdir(dirname(args.output), { recursive: true });
  await Deno.writeTextFile(args.output, await render(args));
}

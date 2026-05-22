/** E2E run diagnostics collection — metadata, HTTP probes, log bundling. @module diagnostics */
import { join } from "@std/path";
import { copy, exists } from "@std/fs";
import { loadTopologyManifest, logInfo } from "@garazyk/schemat";

const BASE_DIR = "/tmp/garazyk-atproto-e2e";

const SECRET_PATTERNS = [
  /(Authorization:\s*Bearer\s+)[A-Za-z0-9._~+/=-]+/gi,
  /("(?:accessJwt|refreshJwt|token|password|secret|masterSecret|adminPassword)"\s*:\s*")[^"]+"/gi,
  /((?:JWT|TOKEN|PASSWORD|SECRET|MASTER_SECRET|ADMIN_SECRET)=)\S+/g,
];

/** Context for a single E2E run, holding paths for logs, reports, and diagnostics. */
export interface E2ERunContext {
  /** Run identifier for the current execution. */
  runId: string;
  /** Directory that contains all run artifacts. */
  runDir: string;
  /** Directory that contains service logs. */
  logsDir: string;
  /** Directory that contains scenario reports. */
  reportsDir: string;
  /** Directory that contains collected diagnostics. */
  diagnosticsDir: string;
  /** Path to the PID file for tracked processes. */
  pidFile: string;
  /** Docker Compose project name for the run. */
  composeProject: string;
}

function sanitizeRunId(value: string): string {
  const cleaned = value.trim().replace(/[^A-Za-z0-9_.-]+/g, "-").replace(
    /^-+|-+$/g,
    "",
  )
    .toLowerCase();
  return cleaned || defaultRunId();
}

function defaultRunId(): string {
  const now = new Date().toISOString().replace(/[:.]/g, "").substring(0, 15) +
    "Z";
  return `${now}-${Deno.pid}`;
}

/** Create the E2E run context, ensuring all directories exist. */
export async function createRunContext(
  runId?: string,
  diagnosticsDir?: string,
  runDir?: string,
): Promise<E2ERunContext> {
  const resolvedRunId = sanitizeRunId(
    runId || Deno.env.get("ATPROTO_E2E_RUN_ID") || defaultRunId(),
  );
  const baseDir = Deno.env.get("ATPROTO_E2E_BASE_DIR") || BASE_DIR;
  const resolvedRunDir = runDir || Deno.env.get("ATPROTO_E2E_RUN_DIR") ||
    join(baseDir, resolvedRunId);
  const resolvedLogsDir = Deno.env.get("ATPROTO_E2E_LOG_DIR") ||
    join(resolvedRunDir, "logs");
  const resolvedReportsDir = Deno.env.get("ATPROTO_E2E_REPORTS_DIR") ||
    join(resolvedRunDir, "reports");
  const resolvedDiagDir = diagnosticsDir ||
    Deno.env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") ||
    join(resolvedRunDir, "diagnostics");
  const resolvedPidFile = Deno.env.get("ATPROTO_E2E_PID_FILE") ||
    join(resolvedRunDir, "pids.txt");

  const composeRunId = resolvedRunId.replace(/[^a-z0-9-]+/g, "-");
  const composeProject = Deno.env.get("ATPROTO_E2E_COMPOSE_PROJECT") ||
    `garazyk-e2e-${composeRunId}`;

  for (
    const path of [
      resolvedRunDir,
      resolvedLogsDir,
      resolvedReportsDir,
      resolvedDiagDir,
    ]
  ) {
    await Deno.mkdir(path, { recursive: true });
  }

  Deno.env.set("ATPROTO_E2E_RUN_ID", resolvedRunId);
  Deno.env.set("ATPROTO_E2E_RUN_DIR", resolvedRunDir);
  Deno.env.set("ATPROTO_E2E_LOG_DIR", resolvedLogsDir);
  Deno.env.set("ATPROTO_E2E_REPORTS_DIR", resolvedReportsDir);
  Deno.env.set("ATPROTO_E2E_DIAGNOSTICS_DIR", resolvedDiagDir);
  Deno.env.set("ATPROTO_E2E_PID_FILE", resolvedPidFile);
  Deno.env.set("ATPROTO_E2E_COMPOSE_PROJECT", composeProject);

  return {
    runId: resolvedRunId,
    runDir: resolvedRunDir,
    logsDir: resolvedLogsDir,
    reportsDir: resolvedReportsDir,
    diagnosticsDir: resolvedDiagDir,
    pidFile: resolvedPidFile,
    composeProject,
  };
}

/** Redact sensitive diagnostic text while preserving JSON string delimiters. */
export function redactDiagnosticText(value: string): string {
  let redacted = value;
  for (const pattern of SECRET_PATTERNS) {
    redacted = redacted.replace(pattern, (match, p1) => {
      if (match.startsWith('"')) {
        return `${p1}[REDACTED]"`;
      }
      return `${p1}[REDACTED]`;
    });
  }
  return redacted;
}

async function writeText(path: string, text: string) {
  await Deno.mkdir(join(path, ".."), { recursive: true });
  await Deno.writeTextFile(path, redactDiagnosticText(text));
}

async function collectHttpEndpoint(
  outputDir: string,
  name: string,
  url: string,
  headers: Record<string, string> = {},
  timeout = 8000,
) {
  const target = join(outputDir, "http", `${name}.txt`);
  let text: string;
  try {
    const controller = new AbortController();
    const id = setTimeout(() => controller.abort(), timeout);
    const resp = await fetch(url, { headers, signal: controller.signal });
    clearTimeout(id);
    const body = (await resp.text()).substring(0, 50000);
    text = `url=${url}\nhttp_status=${resp.status}\ncontent_type=${
      resp.headers.get("Content-Type") || ""
    }\n\n${body}\n`;
  } catch (exc) {
    text = `url=${url}\nerror=${exc}\n`;
  }
  await writeText(target, text);
}

/** Collect Docker diagnostics: ps, config, and logs. */
async function collectDockerDiagnostics(
  dir: string,
  composeProject: string,
  composeFiles: string[],
): Promise<void> {
  const dockerDir = join(dir, "docker");
  await Deno.mkdir(dockerDir, { recursive: true });

  const composeBase = ["compose", "-p", composeProject];
  if (composeFiles.length > 0) {
    for (const f of composeFiles) {
      composeBase.push("-f", f);
    }
  }

  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [...composeBase, "ps", "--all"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await writeText(
      join(dockerDir, "ps.txt"),
      new TextDecoder().decode(stdout),
    );
  } catch { /* ignore */ }

  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [...composeBase, "config"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await writeText(
      join(dockerDir, "config.txt"),
      new TextDecoder().decode(stdout),
    );
  } catch { /* ignore */ }

  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [
        ...composeBase,
        "logs",
        "--no-color",
        "--timestamps",
        "--tail=3000",
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await writeText(
      join(dockerDir, "logs.txt"),
      new TextDecoder().decode(stdout),
    );
  } catch { /* ignore */ }
}

/** Collect diagnostics for the current run: metadata, git info, service logs, HTTP probes. */
export async function collectDiagnostics(
  context: E2ERunContext,
  options: {
    serviceUrls?: Record<string, string>;
    appviewAdminSecret?: string;
    label?: string;
    composeFiles?: string[];
  } = {},
): Promise<string> {
  const outputDir = context.diagnosticsDir;
  await Deno.mkdir(outputDir, { recursive: true });
  const manifest = loadTopologyManifest();
  const defaultUrls: Record<string, string> = {
    plc: Deno.env.get("PLC_URL") || "http://localhost:2582",
    pds: Deno.env.get("PDS_URL") || "http://localhost:2583",
    pds2: Deno.env.get("PDS2_URL") || "http://localhost:2587",
    relay: Deno.env.get("RELAY_URL") || "http://localhost:2584",
    appview: Deno.env.get("APPVIEW_URL") || "http://localhost:3200",
    chat: Deno.env.get("CHAT_URL") || "http://localhost:2585",
    video: Deno.env.get("VIDEO_URL") || "http://localhost:2586",
    ui: Deno.env.get("GARAZYK_UI_URL") || "http://localhost:2590",
  };
  const urls = {
    ...defaultUrls,
    ...(manifest?.serviceUrls || {}),
    ...options.serviceUrls,
  };
  const appviewSecret = options.appviewAdminSecret ||
    Deno.env.get("APPVIEW_ADMIN_SECRET") ||
    "localdevadmin";
  const label = options.label || "atproto-e2e";

  const metadata: Record<string, unknown> = {
    label,
    run_id: context.runId,
    run_dir: context.runDir,
    diagnostics_dir: outputDir,
    compose_project: context.composeProject,
    created_at_utc: new Date().toISOString(),
    service_urls: urls,
  };

  try {
    const gitHead = new Deno.Command("git", { args: ["rev-parse", "HEAD"] })
      .outputSync();
    metadata.git_commit = new TextDecoder().decode(gitHead.stdout).trim();
    const gitStatus = new Deno.Command("git", { args: ["status", "--short"] })
      .outputSync();
    metadata.git_status = new TextDecoder().decode(gitStatus.stdout).trim()
      .split("\n");
  } catch (e) {
    metadata.git_error = String(e);
  }

  await writeText(
    join(outputDir, "run-metadata.json"),
    JSON.stringify(metadata, null, 2),
  );

  if (await exists(context.pidFile)) {
    await copy(context.pidFile, join(outputDir, "pids.txt"), {
      overwrite: true,
    });
  }

  if (await exists(context.logsDir)) {
    const logsOut = join(outputDir, "service-logs");
    await Deno.mkdir(logsOut, { recursive: true });
    for await (const entry of Deno.readDir(context.logsDir)) {
      if (entry.isFile && entry.name.endsWith(".log")) {
        await copy(
          join(context.logsDir, entry.name),
          join(logsOut, entry.name),
          {
            overwrite: true,
          },
        );
      }
    }
  }

  const authHeader = { "Authorization": `Bearer ${appviewSecret}` };

  const probes = manifest?.diagnostics?.length ? manifest.diagnostics : [
    { name: "plc-health", url: `${urls.plc}/_health`, headers: {} },
    {
      name: "pds-describe-server",
      url: `${urls.pds}/xrpc/com.atproto.server.describeServer`,
      headers: {},
    },
    {
      name: "relay-health",
      url: `${urls.relay}/api/relay/health`,
      headers: {},
    },
    {
      name: "relay-upstreams",
      url: `${urls.relay}/api/relay/upstreams`,
      headers: {},
    },
    {
      name: "appview-backfill-status",
      url: `${urls.appview}/admin/backfill/status`,
      headers: authHeader,
    },
    {
      name: "appview-backfill-queue",
      url: `${urls.appview}/admin/backfill/queue?limit=10`,
      headers: authHeader,
    },
    {
      name: "appview-ingest-health",
      url: `${urls.appview}/admin/ingest/health`,
      headers: authHeader,
    },
    {
      name: "appview-metrics-stats",
      url: `${urls.appview}/admin/appview/metrics/stats`,
      headers: authHeader,
    },
    {
      name: "appview-lexicons",
      url: `${urls.appview}/admin/lexicons`,
      headers: authHeader,
    },
    {
      name: "appview-hooks",
      url: `${urls.appview}/admin/hooks`,
      headers: authHeader,
    },
    {
      name: "appview-endpoints",
      url: `${urls.appview}/admin/endpoints`,
      headers: authHeader,
    },
    {
      name: "pds2-describe-server",
      url: `${urls.pds2}/xrpc/com.atproto.server.describeServer`,
      headers: {},
    },
    { name: "chat-health", url: `${urls.chat}/_health`, headers: {} },
    { name: "video-health", url: `${urls.video}/_health`, headers: {} },
    { name: "ui-admin", url: `${urls.ui}/admin`, headers: {} },
  ];

  await Promise.all(
    probes.map((probe) =>
      collectHttpEndpoint(outputDir, probe.name, probe.url, probe.headers)
    ),
  );

  if (options.composeFiles && options.composeFiles.length > 0) {
    await collectDockerDiagnostics(
      outputDir,
      context.composeProject,
      options.composeFiles,
    );
  } else if (!Deno.env.get("ATPROTO_BINARY_MODE")) {
    // Try to collect docker diagnostics using just the project name if files aren't provided
    await collectDockerDiagnostics(
      outputDir,
      context.composeProject,
      [],
    );
  }

  logInfo(`Diagnostics written to ${outputDir}`);
  return outputDir;
}

import { join, resolve } from "@std/path";
import { copy, exists } from "@std/fs";
import { SERVICE_URLS } from "./config.ts";

const BASE_DIR = "/tmp/garazyk-atproto-e2e";

const SECRET_PATTERNS = [
  /(Authorization:\s*Bearer\s+)[A-Za-z0-9._~+/=-]+/gi,
  /("(?:accessJwt|refreshJwt|token|password|secret|masterSecret|adminPassword)"\s*:\s*")[^"]+"/gi,
  /((?:JWT|TOKEN|PASSWORD|SECRET|MASTER_SECRET|ADMIN_SECRET)=)\S+/g,
];

export interface E2ERunContext {
  runId: string;
  runDir: string;
  logsDir: string;
  reportsDir: string;
  diagnosticsDir: string;
  pidFile: string;
  composeProject: string;
}

function sanitizeRunId(value: string): string {
  const cleaned = value.trim().replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^-+|-+$/g, "")
    .toLowerCase();
  return cleaned || defaultRunId();
}

function defaultRunId(): string {
  const now = new Date().toISOString().replace(/[:.]/g, "").substring(0, 15) + "Z";
  return `${now}-${Deno.pid}`;
}

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
  const resolvedLogsDir = Deno.env.get("ATPROTO_E2E_LOG_DIR") || join(resolvedRunDir, "logs");
  const resolvedReportsDir = Deno.env.get("ATPROTO_E2E_REPORTS_DIR") ||
    join(resolvedRunDir, "reports");
  const resolvedDiagDir = diagnosticsDir || Deno.env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") ||
    join(resolvedRunDir, "diagnostics");
  const resolvedPidFile = Deno.env.get("ATPROTO_E2E_PID_FILE") || join(resolvedRunDir, "pids.txt");

  const composeRunId = resolvedRunId.replace(/[^a-z0-9-]+/g, "-");
  const composeProject = Deno.env.get("ATPROTO_E2E_COMPOSE_PROJECT") ||
    `garazyk-e2e-${composeRunId}`;

  for (const path of [resolvedRunDir, resolvedLogsDir, resolvedReportsDir, resolvedDiagDir]) {
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

function redact(value: string): string {
  let redacted = value;
  for (const pattern of SECRET_PATTERNS) {
    redacted = redacted.replace(pattern, (match, p1) => {
      if (match.toLowerCase().includes("accessjwt")) {
        return `${p1}[REDACTED]"`;
      }
      return `${p1}[REDACTED]`;
    });
  }
  return redacted;
}

async function writeText(path: string, text: string) {
  await Deno.mkdir(join(path, ".."), { recursive: true });
  await Deno.writeTextFile(path, redact(text));
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

export async function collectDiagnostics(
  context: E2ERunContext,
  options: {
    serviceUrls?: Record<string, string>;
    appviewAdminSecret?: string;
    label?: string;
  } = {},
): Promise<string> {
  const outputDir = context.diagnosticsDir;
  await Deno.mkdir(outputDir, { recursive: true });
  const urls = { ...SERVICE_URLS, ...options.serviceUrls };
  const appviewSecret = options.appviewAdminSecret || Deno.env.get("APPVIEW_ADMIN_SECRET") ||
    "localdevadmin";
  const label = options.label || "atproto-e2e";

  const metadata: Record<string, any> = {
    label,
    run_id: context.runId,
    run_dir: context.runDir,
    diagnostics_dir: outputDir,
    compose_project: context.composeProject,
    created_at_utc: new Date().toISOString(),
    service_urls: urls,
  };

  try {
    const gitHead = new Deno.Command("git", { args: ["rev-parse", "HEAD"] }).outputSync();
    metadata.git_commit = new TextDecoder().decode(gitHead.stdout).trim();
    const gitStatus = new Deno.Command("git", { args: ["status", "--short"] }).outputSync();
    metadata.git_status = new TextDecoder().decode(gitStatus.stdout).trim().split("\n");
  } catch (e) {
    metadata.git_error = String(e);
  }

  await writeText(join(outputDir, "run-metadata.json"), JSON.stringify(metadata, null, 2));

  if (await exists(context.pidFile)) {
    await copy(context.pidFile, join(outputDir, "pids.txt"), { overwrite: true });
  }

  if (await exists(context.logsDir)) {
    const logsOut = join(outputDir, "service-logs");
    await Deno.mkdir(logsOut, { recursive: true });
    for await (const entry of Deno.readDir(context.logsDir)) {
      if (entry.isFile && entry.name.endsWith(".log")) {
        await copy(join(context.logsDir, entry.name), join(logsOut, entry.name), {
          overwrite: true,
        });
      }
    }
  }

  const authHeader = { "Authorization": `Bearer ${appviewSecret}` };

  await Promise.all([
    collectHttpEndpoint(outputDir, "plc-health", `${urls.plc}/_health`),
    collectHttpEndpoint(
      outputDir,
      "pds-describe-server",
      `${urls.pds}/xrpc/com.atproto.server.describeServer`,
    ),
    collectHttpEndpoint(outputDir, "relay-health", `${urls.relay}/api/relay/health`),
    collectHttpEndpoint(outputDir, "relay-upstreams", `${urls.relay}/api/relay/upstreams`),
    collectHttpEndpoint(
      outputDir,
      "appview-backfill-status",
      `${urls.appview}/admin/backfill/status`,
      authHeader,
    ),
    collectHttpEndpoint(
      outputDir,
      "appview-backfill-queue",
      `${urls.appview}/admin/backfill/queue?limit=10`,
      authHeader,
    ),
    collectHttpEndpoint(
      outputDir,
      "appview-ingest-health",
      `${urls.appview}/admin/ingest/health`,
      authHeader,
    ),
    collectHttpEndpoint(
      outputDir,
      "appview-metrics-stats",
      `${urls.appview}/admin/appview/metrics/stats`,
      authHeader,
    ),
    collectHttpEndpoint(
      outputDir,
      "appview-lexicons",
      `${urls.appview}/admin/lexicons`,
      authHeader,
    ),
    collectHttpEndpoint(outputDir, "appview-hooks", `${urls.appview}/admin/hooks`, authHeader),
    collectHttpEndpoint(
      outputDir,
      "appview-endpoints",
      `${urls.appview}/admin/endpoints`,
      authHeader,
    ),
    collectHttpEndpoint(
      outputDir,
      "pds2-describe-server",
      `${urls.pds2}/xrpc/com.atproto.server.describeServer`,
    ),
    collectHttpEndpoint(outputDir, "chat-health", `${urls.chat}/_health`),
    collectHttpEndpoint(outputDir, "video-health", `${urls.video}/_health`),
    collectHttpEndpoint(outputDir, "ui-admin", `${urls.ui}/admin`),
  ]);

  return outputDir;
}

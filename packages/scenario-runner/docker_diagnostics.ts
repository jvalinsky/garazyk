/**
 * Diagnostics collection for the local ATProto network.
 *
 * Collects HTTP endpoint responses, Docker container state, and
 * run metadata into a structured diagnostics directory.
 *
 * @module docker_diagnostics
 */

import { join } from "@std/path";
import { repoRoot, serviceUrl } from "@garazyk/atproto-topology";
import type { RunContext } from "@garazyk/docker-client";

/**
 * Collect run metadata, HTTP endpoint snapshots, and optional Docker state.
 *
 * @param ctx - Run context containing the diagnostics directory.
 * @param composeFiles - Optional compose files to inspect.
 * @returns Resolves when diagnostics have been written.
 */
export async function collectDiagnostics(
  ctx: RunContext,
  composeFiles?: string[],
): Promise<void> {
  const dir = ctx.diagnosticsDir;
  Deno.mkdirSync(dir, { recursive: true });

  await writeRunMetadata(dir);

  const endpoints: Array<[string, string, Record<string, string>?]> = [
    ["plc-health", `${serviceUrl("plc")}/_health`],
    [
      "pds-describe-server",
      `${serviceUrl("pds")}/xrpc/com.atproto.server.describeServer`,
    ],
    ["relay-health", `${serviceUrl("relay")}/api/relay/health`],
    ["relay-upstreams", `${serviceUrl("relay")}/api/relay/upstreams`],
    [
      "appview-backfill-status",
      `${serviceUrl("appview")}/admin/backfill/status`,
      {
        "Authorization": "Bearer localdevadmin",
      },
    ],
    [
      "pds2-describe-server",
      `${serviceUrl("pds2")}/xrpc/com.atproto.server.describeServer`,
    ],
    ["chat-health", `${serviceUrl("chat")}/_health`],
    ["video-health", `${serviceUrl("video")}/_health`],
  ];

  for (const [name, url, headers] of endpoints) {
    await collectHttpEndpoint(dir, name, url, headers);
  }

  if (composeFiles && composeFiles.length > 0) {
    await collectDockerDiagnostics(dir, ctx.composeProject, composeFiles);
  }

  console.log(`[INFO]  Diagnostics written to ${dir}`);
}

async function writeRunMetadata(dir: string): Promise<void> {
  const root = await repoRoot();
  const lines: string[] = [
    `run_id=${Deno.env.get("ATPROTO_E2E_RUN_ID") || "unknown"}`,
    `run_dir=${Deno.env.get("ATPROTO_E2E_RUN_DIR") || "unknown"}`,
    `diagnostics_dir=${
      Deno.env.get("ATPROTO_E2E_DIAGNOSTICS_DIR") || "unknown"
    }`,
    `compose_project=${Deno.env.get("ATPROTO_E2E_COMPOSE_PROJECT") || ""}`,
    `repo_root=${root}`,
    `created_at_utc=${new Date().toISOString()}`,
  ];

  try {
    const { stdout } = await new Deno.Command("git", {
      args: ["-C", root, "rev-parse", "HEAD"],
      stdout: "piped",
    }).output();
    lines.push(`git_commit=${new TextDecoder().decode(stdout).trim()}`);
  } catch {
    /* ignore */
  }

  await Deno.writeTextFile(
    join(dir, "run-metadata.txt"),
    lines.join("\n") + "\n",
  );
}

async function collectHttpEndpoint(
  dir: string,
  name: string,
  url: string,
  headers?: Record<string, string>,
): Promise<void> {
  const httpDir = join(dir, "http");
  Deno.mkdirSync(httpDir, { recursive: true });

  try {
    const resp = await fetch(url, {
      headers,
      signal: AbortSignal.timeout(8000),
    });
    const body = await resp.text();
    const content = `url=${url}\nhttp_status=${resp.status}\ncontent_type=${
      resp.headers.get("content-type") || ""
    }\n\n${body}`;
    await Deno.writeTextFile(join(httpDir, `${name}.txt`), content);
  } catch (err) {
    await Deno.writeTextFile(
      join(httpDir, `${name}.txt`),
      `url=${url}\nerror=${err}\n`,
    );
  }
}

async function collectDockerDiagnostics(
  dir: string,
  composeProject: string,
  composeFiles: string[],
): Promise<void> {
  const dockerDir = join(dir, "docker");
  Deno.mkdirSync(dockerDir, { recursive: true });

  const composeBase = ["compose", "-p", composeProject];
  for (const f of composeFiles) {
    composeBase.push("-f", f);
  }

  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [...composeBase, "ps", "--all"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await Deno.writeTextFile(
      join(dockerDir, "ps.txt"),
      new TextDecoder().decode(stdout),
    );
  } catch {
    /* cleanup */
  }

  try {
    const { stdout } = await new Deno.Command("docker", {
      args: [...composeBase, "config"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    await Deno.writeTextFile(
      join(dockerDir, "config.txt"),
      new TextDecoder().decode(stdout),
    );
  } catch {
    /* cleanup */
  }

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
    await Deno.writeTextFile(
      join(dockerDir, "logs.txt"),
      new TextDecoder().decode(stdout),
    );
  } catch {
    /* cleanup */
  }
}

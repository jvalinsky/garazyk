#!/usr/bin/env -S deno run -A
import { dirname, fromFileUrl, join, relative, resolve } from "jsr:@std/path@1";

type Classification =
  | "canonical"
  | "archive"
  | "entrypoint"
  | "internal-reference";

interface DocRecord {
  path: string;
  classification: Classification;
  canonical_target: string;
  owner: string;
  status: string;
}

interface LinkIssue {
  source: string;
  line: number;
  href: string;
  message: string;
}

interface LinkEdge {
  source: string;
  target: string;
  href: string;
  line: number;
}

const ROOT = resolve(dirname(fromFileUrl(import.meta.url)), "../..");
const DOCS = join(ROOT, "docs");
const METADATA_DIR = join(DOCS, "metadata");
const REPORTS_DIR = join(DOCS, "reports", "docs");
const INDEX_DIR = join(DOCS, "repo-index");

const REGISTRY_PATH = join(METADATA_DIR, "doc-registry.json");
const REGISTRY_SCHEMA_PATH = join(METADATA_DIR, "doc-registry.schema.json");
const GRAPH_PATH = join(METADATA_DIR, "doc-link-graph.json");
const ORPHAN_JSON_PATH = join(METADATA_DIR, "doc-orphans.json");
const MIGRATION_MAP_PATH = join(METADATA_DIR, "doc-migration-map.json");
const EXTERNAL_REPORT_PATH = join(METADATA_DIR, "external-links-report.json");
const ORPHAN_ALLOWLIST_PATH = join(METADATA_DIR, "orphan-allowlist.txt");

const CANONICAL_DOC_RE = /^docs\/(0[1-9]|1[0-2])-[^/]+\//;
const MD_LINK_RE = /\[([^\]]+)\]\(([^)]+)\)/g;
const URL_SCHEME_RE = /^(?:https?|mailto|tel|ftp|data):/i;
const CANONICAL_DEFAULT = "docs/index.md";

const ROOT_ENTRYPOINTS = new Set([
  "README.md",
  "BUILD.md",
  "CONTRIBUTING.md",
  "DOCUMENTATION.md",
  "AGENTS.md",
  "AGENTS_QUICKREF.md",
  "ADMINUI_START_HERE.md",
  "ADMINUI_QUICKSTART.md",
  "ADMINUI_PROJECT_COMPLETE.md",
  "ADMINUI_DEPLOYMENT_GUIDE.md",
]);

const TOP_LEVEL_MARKDOWN_DIRS = [
  "docs",
  "Garazyk",
  "examples",
  "tooling",
  "scripts",
  "skills",
];
const SCAN_DIR_SKIP_NAMES = new Set([
  ".git",
  "node_modules",
  ".vitepress",
  "dist",
  "build",
  "build-linux",
  ".cache",
  ".cadmus",
  ".ruff_cache",
  ".claude",
  ".deciduous",
  ".letta",
  "vendor",
  "blobs",
  "cache",
  "did_cache",
  "keys",
  "sequencer",
]);

function posixRel(path: string): string {
  return relative(ROOT, path).replaceAll("\\", "/");
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

async function ensureDirs() {
  for (const dir of [METADATA_DIR, REPORTS_DIR, INDEX_DIR]) {
    await Deno.mkdir(dir, { recursive: true });
  }
}

async function* walkMarkdown(dir: string): AsyncGenerator<string> {
  for await (const entry of Deno.readDir(dir)) {
    if (entry.name.startsWith(".") || SCAN_DIR_SKIP_NAMES.has(entry.name)) {
      continue;
    }
    const path = join(dir, entry.name);
    if (entry.isDirectory) {
      yield* walkMarkdown(path);
    } else if (entry.isFile && entry.name.endsWith(".md")) {
      yield path;
    }
  }
}

async function discoverMarkdownFiles(): Promise<string[]> {
  const files = new Set<string>();
  for (const relDir of TOP_LEVEL_MARKDOWN_DIRS) {
    const dir = join(ROOT, relDir);
    if (!await exists(dir)) continue;
    for await (const file of walkMarkdown(dir)) files.add(resolve(file));
  }
  for await (const entry of Deno.readDir(ROOT)) {
    const path = join(ROOT, entry.name);
    if (entry.isFile && entry.name.endsWith(".md")) files.add(resolve(path));
  }
  return [...files].sort((a, b) => posixRel(a).localeCompare(posixRel(b)));
}

function classifyDoc(path: string): Classification {
  if (CANONICAL_DOC_RE.test(path)) return "canonical";
  if (["docs/index.md", "docs/README.md", "docs/SUMMARY.md"].includes(path)) {
    return "canonical";
  }
  if (
    path.startsWith("docs/archive/") || path.startsWith("docs/scratchpad/") ||
    path.startsWith("docs/plans/archive/") || path.startsWith("docs/plan/")
  ) return "archive";
  if (
    ROOT_ENTRYPOINTS.has(path) ||
    (path.startsWith("ADMINUI_") && path.endsWith(".md"))
  ) {
    return "entrypoint";
  }
  return "internal-reference";
}

function inferOwner(path: string): string {
  if (path.startsWith("docs/")) {
    if (path.startsWith("docs/security/")) return "security";
    if (path.startsWith("docs/tests/")) return "quality";
    if (path.startsWith("docs/plans/")) return "planning";
    return "docs";
  }
  if (path.startsWith("Garazyk/Sources/Admin/")) return "admin";
  if (path.startsWith("Garazyk/")) return "core";
  if (path.startsWith("tooling/")) return "tooling";
  if (path.startsWith("skills/")) return "skills";
  if (path.startsWith("scripts/")) return "tooling";
  if (path.startsWith("examples/")) return "docs";
  return "docs";
}

function inferStatus(classification: Classification): string {
  if (classification === "canonical" || classification === "entrypoint") {
    return "active";
  }
  if (classification === "archive") return "archived";
  return "reference";
}

function inferCanonicalTarget(
  path: string,
  classification: Classification,
): string {
  if (classification === "canonical") return path;

  const explicit: Record<string, string> = {
    "README.md": "docs/index.md",
    "BUILD.md": "docs/01-getting-started/setup.md",
    "CONTRIBUTING.md": "docs/index.md",
    "DOCUMENTATION.md": "docs/11-reference/documentation-map.md",
    "AGENTS.md": "docs/11-reference/documentation-map.md",
    "AGENTS_QUICKREF.md": "docs/11-reference/documentation-map.md",
    "ADMINUI_START_HERE.md": "docs/11-reference/admin-ui-documentation.md",
    "ADMINUI_QUICKSTART.md": "docs/11-reference/admin-ui-documentation.md",
    "ADMINUI_PROJECT_COMPLETE.md": "docs/11-reference/admin-ui-documentation.md",
    "ADMINUI_DEPLOYMENT_GUIDE.md": "docs/11-reference/admin-ui-documentation.md",
  };
  if (explicit[path]) return explicit[path];
  if (path.startsWith("docs/security/")) {
    return "docs/11-reference/security-audit-guide.md";
  }
  if (path.startsWith("docs/tests/")) return "docs/11-reference/testing-map.md";
  if (path.startsWith("docs/oauth2/")) {
    return "docs/06-authentication/oauth2-dpop.md";
  }
  if (path.startsWith("docs/architecture/")) {
    return "docs/01-getting-started/architecture-overview.md";
  }
  if (path.startsWith("docs/guides/")) return "docs/index.md";
  if (path.startsWith("docs/plans/") || path.startsWith("docs/plan/")) {
    return "docs/archive/planning/README.md";
  }
  if (path.startsWith("docs/scratchpad/")) {
    return "docs/archive/planning/README.md";
  }
  if (path.startsWith("Garazyk/Sources/Admin/")) {
    return "docs/11-reference/admin-ui-documentation.md";
  }
  if (path.startsWith("Garazyk/")) {
    return "docs/11-reference/source-adjacent-documentation.md";
  }
  if (path.startsWith("skills/")) {
    return "docs/11-reference/tooling-and-skills-documentation.md";
  }
  if (path.startsWith("tooling/")) {
    return "docs/11-reference/tooling-and-skills-documentation.md";
  }
  if (path.startsWith("scripts/")) {
    return "docs/11-reference/tooling-and-skills-documentation.md";
  }
  if (path.startsWith("examples/")) return "docs/10-tutorials/index.md";
  return CANONICAL_DEFAULT;
}

function buildRegistry(files: string[]): DocRecord[] {
  return files.map((file) => {
    const path = posixRel(file);
    const classification = classifyDoc(path);
    return {
      path,
      classification,
      canonical_target: inferCanonicalTarget(path, classification),
      owner: inferOwner(path),
      status: inferStatus(classification),
    };
  }).sort((a, b) => a.path.localeCompare(b.path));
}

async function writeRegistrySchema() {
  await writeJson(REGISTRY_SCHEMA_PATH, {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    title: "Garazyk Doc Registry",
    type: "array",
    items: {
      type: "object",
      required: [
        "path",
        "classification",
        "canonical_target",
        "owner",
        "status",
      ],
      properties: {
        path: { type: "string" },
        classification: {
          type: "string",
          enum: ["canonical", "archive", "entrypoint", "internal-reference"],
        },
        canonical_target: { type: "string" },
        owner: { type: "string" },
        status: { type: "string" },
      },
      additionalProperties: false,
    },
  });
}

function cleanHref(href: string): string {
  let value = href.trim();
  if (value.startsWith("<") && value.endsWith(">")) {
    value = value.slice(1, -1).trim();
  }
  return value;
}

function removeFragmentAndQuery(href: string): string {
  return href.split("#", 1)[0].split("?", 1)[0];
}

async function resolveInternalTarget(
  source: string,
  hrefRaw: string,
): Promise<string | null> {
  const href = cleanHref(hrefRaw);
  if (!href || href.startsWith("#")) return null;
  const link = removeFragmentAndQuery(href);
  if (!link) return null;

  const candidates: string[] = [];
  if (link.startsWith("/")) {
    const trimmed = link.replace(/^\/+/, "");
    candidates.push(join(ROOT, trimmed), join(DOCS, trimmed));
  } else {
    candidates.push(resolve(join(dirname(source), link)));
  }

  const expanded: string[] = [];
  for (const candidate of candidates) {
    expanded.push(candidate);
    if (!candidate.split("/").at(-1)?.includes(".")) {
      expanded.push(
        `${candidate}.md`,
        join(candidate, "README.md"),
        join(candidate, "index.md"),
      );
    }
  }
  for (const candidate of expanded) {
    if (await exists(candidate)) return resolve(candidate);
  }
  return null;
}

function* iterMarkdownLinks(
  content: string,
): Generator<[number, string, string]> {
  const lines = content.split("\n");
  for (let i = 0; i < lines.length; i++) {
    for (const match of lines[i].matchAll(MD_LINK_RE)) {
      yield [i + 1, match[1], match[2]];
    }
  }
}

async function analyzeLinks(files: string[], records: DocRecord[]) {
  const recordPaths = new Set(records.map((record) => record.path));
  const edges: LinkEdge[] = [];
  const issues: LinkIssue[] = [];
  const outgoing: Record<string, string[]> = {};
  const stats = { internal: 0, external: 0, anchor: 0, missing: 0 };
  const externalCounts: Record<string, number> = {};

  for (
    const source of files.toSorted((a, b) => posixRel(a).localeCompare(posixRel(b)))
  ) {
    const rel = posixRel(source);
    outgoing[rel] = [];
    const content = await Deno.readTextFile(source).catch(() => "");
    for (const [line, _text, rawHref] of iterMarkdownLinks(content)) {
      const href = cleanHref(rawHref);
      if (!href) continue;
      if (href.startsWith("#")) {
        stats.anchor++;
        continue;
      }
      if (URL_SCHEME_RE.test(href)) {
        stats.external++;
        externalCounts[href] = (externalCounts[href] ?? 0) + 1;
        continue;
      }
      stats.internal++;
      const resolved = await resolveInternalTarget(source, href);
      if (!resolved) {
        stats.missing++;
        issues.push({
          source: rel,
          line,
          href,
          message: "Unresolved internal link",
        });
        continue;
      }
      const targetRel = posixRel(resolved);
      outgoing[rel].push(targetRel);
      if (recordPaths.has(targetRel)) {
        edges.push({ source: rel, target: targetRel, href, line });
      }
    }
  }

  return {
    edges,
    issues,
    outgoing,
    stats,
    externalCounts: Object.fromEntries(
      Object.entries(externalCounts).sort(([a], [b]) => a.localeCompare(b)),
    ),
  };
}

async function loadOrphanAllowlist(): Promise<Set<string>> {
  if (!await exists(ORPHAN_ALLOWLIST_PATH)) return new Set();
  const text = await Deno.readTextFile(ORPHAN_ALLOWLIST_PATH);
  return new Set(
    text.split("\n").map((line) => line.trim()).filter((line) => line && !line.startsWith("#")),
  );
}

async function computeOrphans(records: DocRecord[], edges: LinkEdge[]) {
  const inbound: Record<string, number> = Object.fromEntries(
    records.map((record) => [record.path, 0]),
  );
  for (const edge of edges) {
    if (edge.target in inbound) inbound[edge.target]++;
  }
  const allowlist = await loadOrphanAllowlist();
  const orphans = records
    .filter((record) => inbound[record.path] === 0 && !allowlist.has(record.path))
    .map((record) => record.path)
    .sort();
  return { orphans, inbound };
}

async function writeJson(path: string, payload: unknown) {
  await Deno.mkdir(dirname(path), { recursive: true });
  await Deno.writeTextFile(path, JSON.stringify(payload, null, 2) + "\n");
}

function relativeLink(fromPath: string, toRel: string): string {
  return relative(dirname(fromPath), join(ROOT, toRel)).replaceAll("\\", "/");
}

async function writeMarkdown(path: string, content: string) {
  await Deno.mkdir(dirname(path), { recursive: true });
  await Deno.writeTextFile(path, content.trimEnd() + "\n");
}

function buildCollection(records: DocRecord[], prefix: string): DocRecord[] {
  return records.filter((record) => record.path.startsWith(prefix));
}

function makeRegistryTable(path: string, records: DocRecord[]): string {
  const lines = [
    "| Path | Classification | Canonical Target | Owner | Status |",
    "| --- | --- | --- | --- | --- |",
  ];
  for (const record of records) {
    lines.push(
      `| [${record.path}](${
        relativeLink(path, record.path)
      }) | \`${record.classification}\` | [${record.canonical_target}](${
        relativeLink(path, record.canonical_target)
      }) | \`${record.owner}\` | \`${record.status}\` |`,
    );
  }
  return lines.join("\n");
}

async function generateIndexPages(
  records: DocRecord[],
  inbound: Record<string, number>,
  edges: LinkEdge[],
) {
  const pages: Record<string, DocRecord[]> = {
    "root-entrypoints.md": records.filter((record) => record.classification === "entrypoint"),
    "source-adjacent.md": buildCollection(records, "Garazyk/"),
    "examples.md": buildCollection(records, "examples/"),
    "tooling.md": buildCollection(records, "tooling/"),
    "scripts.md": buildCollection(records, "scripts/"),
    "skills.md": buildCollection(records, "skills/"),
    "docs-noncanonical.md": records.filter((record) =>
      record.path.startsWith("docs/") && record.classification !== "canonical"
    ),
    "all-documents.md": records,
  };

  for (const [filename, pageRecords] of Object.entries(pages)) {
    const page = join(INDEX_DIR, filename);
    const title = filename.replace(".md", "").replaceAll("-", " ").replace(
      /\b\w/g,
      (c) => c.toUpperCase(),
    );
    const intro = [
      "---",
      `title: ${title}`,
      "---",
      `# ${title}`,
      "",
      "Auto-generated documentation index for repository discoverability.",
      "",
      `Total documents in this view: **${pageRecords.length}**`,
      "",
    ];
    await writeMarkdown(
      page,
      `${intro.join("\n")}\n${makeRegistryTable(page, pageRecords)}`,
    );
  }

  const incoming: Record<string, string[]> = {};
  for (const edge of edges) {
    incoming[edge.target] ??= [];
    incoming[edge.target].push(edge.source);
  }

  const backlinks = [
    "---",
    "title: Backlinks",
    "---",
    "# Backlinks",
    "",
    "Auto-generated inbound link inventory for markdown discoverability.",
    "",
  ];
  for (const record of records) {
    backlinks.push(
      `## \`${record.path}\``,
      "",
      `Inbound links: **${inbound[record.path] ?? 0}**`,
      "",
    );
    const sources = [...new Set(incoming[record.path] ?? [])].sort();
    if (sources.length === 0) backlinks.push("- _No inbound links detected._");
    else {
      for (const source of sources) {
        backlinks.push(
          `- [${source}](${relativeLink(join(INDEX_DIR, "backlinks.md"), source)})`,
        );
      }
    }
    backlinks.push("");
  }
  await writeMarkdown(join(INDEX_DIR, "backlinks.md"), backlinks.join("\n"));

  await writeMarkdown(
    join(INDEX_DIR, "index.md"),
    [
      "---",
      "title: Repository Documentation Index",
      "---",
      "# Repository Documentation Index",
      "",
      "Section-level indexes for non-canonical and cross-repository markdown collections.",
      "",
      "## Sections",
      "",
      "- [All Documents](all-documents.md)",
      "- [Root Entrypoints](root-entrypoints.md)",
      "- [Docs Non-Canonical](docs-noncanonical.md)",
      "- [Source-Adjacent](source-adjacent.md)",
      "- [Examples](examples.md)",
      "- [Tooling](tooling.md)",
      "- [Scripts](scripts.md)",
      "- [Skills](skills.md)",
      "- [Backlinks](backlinks.md)",
    ].join("\n"),
  );
}

async function writeOrphanAllowlistIfMissing() {
  if (await exists(ORPHAN_ALLOWLIST_PATH)) return;
  await Deno.writeTextFile(
    ORPHAN_ALLOWLIST_PATH,
    "# Paths allowed to have zero inbound markdown links.\n# Keep this list short.\n",
  );
}

async function defaultMigrationMapIfMissing() {
  if (await exists(MIGRATION_MAP_PATH)) return;
  await writeJson(MIGRATION_MAP_PATH, {
    generated_at: Math.floor(Date.now() / 1000),
    moves: [],
    notes: [
      "Populate this map with old_path/new_path pairs whenever markdown files are moved.",
      "Pointer stubs should be kept at old locations until links are fully migrated.",
    ],
  });
}

async function writeGraphOutputs(
  records: DocRecord[],
  edges: LinkEdge[],
  issues: LinkIssue[],
  inbound: Record<string, number>,
  stats: Record<string, number>,
  externalCounts: Record<string, number>,
) {
  const payload = {
    generated_at: Math.floor(Date.now() / 1000),
    summary: {
      nodes: records.length,
      edges: edges.length,
      internal_links: stats.internal,
      external_links: stats.external,
      anchor_links: stats.anchor,
      missing_internal_links: stats.missing,
    },
    nodes: records.map((record) => ({
      id: record.path,
      classification: record.classification,
      owner: record.owner,
      status: record.status,
      canonical_target: record.canonical_target,
    })),
    edges,
    issues,
    inbound,
    external_link_counts: externalCounts,
  };
  await writeJson(GRAPH_PATH, payload);
  await writeJson(ORPHAN_JSON_PATH, {
    generated_at: Math.floor(Date.now() / 1000),
    orphans: Object.entries(inbound).filter(([, count]) => count === 0).map((
      [path],
    ) => path),
    inbound,
  });

  const report = [
    "---",
    "title: Documentation Link Graph Report",
    "---",
    "# Documentation Link Graph Report",
    "",
    `Generated nodes: **${records.length}**`,
    `Generated edges: **${edges.length}**`,
    `Missing internal links: **${stats.missing}**`,
    "",
    "## Orphans",
    "",
  ];
  const orphans = Object.entries(inbound).filter(([, count]) => count === 0)
    .map(([path]) => path).sort();
  report.push(
    ...(orphans.length
      ? orphans.map((path) => `- \`${path}\``)
      : ["No orphan documents detected."]),
  );
  report.push("", "## Missing Internal Links", "");
  report.push(
    ...(issues.length
      ? issues.slice(0, 500).map((issue) =>
        `- \`${issue.source}:${issue.line}\` -> \`${issue.href}\``
      )
      : ["No unresolved internal markdown links detected."]),
  );
  await writeMarkdown(
    join(REPORTS_DIR, "link-graph-report.md"),
    report.join("\n"),
  );
}

async function runSync(): Promise<number> {
  await ensureDirs();
  await writeOrphanAllowlistIfMissing();
  await writeRegistrySchema();
  await defaultMigrationMapIfMissing();

  for (let pass = 0; pass < 2; pass++) {
    const files = await discoverMarkdownFiles();
    const records = buildRegistry(files);
    const analysis = await analyzeLinks(files, records);
    const { inbound } = await computeOrphans(records, analysis.edges);
    await generateIndexPages(records, inbound, analysis.edges);
  }

  const files = await discoverMarkdownFiles();
  const records = buildRegistry(files);
  const analysis = await analyzeLinks(files, records);
  const { inbound } = await computeOrphans(records, analysis.edges);
  await writeJson(REGISTRY_PATH, records);
  await writeGraphOutputs(
    records,
    analysis.edges,
    analysis.issues,
    inbound,
    analysis.stats,
    analysis.externalCounts,
  );

  console.log(
    `[repo-docs] sync complete: ${records.length} docs, ${analysis.edges.length} graph edges`,
  );
  console.log(`[repo-docs] registry: ${posixRel(REGISTRY_PATH)}`);
  console.log(
    `[repo-docs] index hub: ${posixRel(join(INDEX_DIR, "index.md"))}`,
  );
  return 0;
}

async function loadRegistry(): Promise<DocRecord[]> {
  if (!await exists(REGISTRY_PATH)) {
    console.error("[repo-docs] registry missing; run sync first");
    Deno.exit(2);
  }
  return JSON.parse(await Deno.readTextFile(REGISTRY_PATH));
}

async function validateInternalStrict(records: DocRecord[]) {
  const files = records.map((record) => join(ROOT, record.path)).filter(
    (path) => {
      try {
        return Deno.statSync(path).isFile;
      } catch {
        return false;
      }
    },
  );
  return await analyzeLinks(files, records);
}

async function checkExternalLinks(records: DocRecord[]) {
  const files = records.map((record) => join(ROOT, record.path)).filter(
    (path) => {
      try {
        return Deno.statSync(path).isFile;
      } catch {
        return false;
      }
    },
  );
  const seen = new Set<string>();
  for (const file of files) {
    const content = await Deno.readTextFile(file).catch(() => "");
    for (const [, , hrefRaw] of iterMarkdownLinks(content)) {
      const href = cleanHref(hrefRaw);
      if (href && URL_SCHEME_RE.test(href)) seen.add(href);
    }
  }

  const results: Record<
    string,
    { status: string; code: number | null; message: string }
  > = {};
  for (const url of [...seen].sort()) {
    try {
      const response = await fetch(url, {
        method: "HEAD",
        headers: { "User-Agent": "garazyk-docs-validator/1.0" },
        signal: AbortSignal.timeout(8000),
      });
      results[url] = {
        status: response.status >= 400 ? "error" : "ok",
        code: response.status,
        message: response.status >= 400 ? `HTTP ${response.status}` : "OK",
      };
    } catch (exc) {
      results[url] = {
        status: "warning",
        code: null,
        message: exc instanceof Error ? exc.message : String(exc),
      };
    }
  }
  const payload = {
    generated_at: Math.floor(Date.now() / 1000),
    checked: Object.keys(results).length,
    results,
  };
  await writeJson(EXTERNAL_REPORT_PATH, payload);
  return payload;
}

async function validate(flags: Set<string>): Promise<number> {
  await ensureDirs();
  const records = await loadRegistry();
  let exitCode = 0;
  let analysis = {
    edges: [] as LinkEdge[],
    issues: [] as LinkIssue[],
    outgoing: {} as Record<string, string[]>,
    stats: { internal: 0, external: 0, anchor: 0, missing: 0 },
    externalCounts: {} as Record<string, number>,
  };

  if (flags.has("--internal-strict") || flags.has("--orphans")) {
    analysis = await validateInternalStrict(records);
  }
  if (flags.has("--internal-strict")) {
    if (analysis.issues.length > 0) {
      console.log(
        `[repo-docs] internal strict failed: ${analysis.issues.length} unresolved links`,
      );
      for (const issue of analysis.issues.slice(0, 200)) {
        console.log(
          `  - ${issue.source}:${issue.line} -> ${issue.href} (${issue.message})`,
        );
      }
      exitCode = 1;
    } else {
      console.log("[repo-docs] internal strict passed");
    }
  }
  if (flags.has("--orphans")) {
    const { orphans, inbound } = await computeOrphans(records, analysis.edges);
    await writeGraphOutputs(
      records,
      analysis.edges,
      analysis.issues,
      inbound,
      analysis.stats,
      analysis.externalCounts,
    );
    if (orphans.length > 0) {
      console.log(
        `[repo-docs] orphan check failed: ${orphans.length} orphan docs`,
      );
      for (const orphan of orphans.slice(0, 200)) console.log(`  - ${orphan}`);
      exitCode = 1;
    } else {
      console.log("[repo-docs] orphan check passed");
    }
  }
  if (flags.has("--external-report")) {
    const report = await checkExternalLinks(records);
    const bad = Object.values(report.results).filter((info) =>
      ["error", "warning"].includes(info.status)
    );
    console.log(
      `[repo-docs] external report complete: checked=${report.checked} issues=${bad.length}`,
    );
  }
  return exitCode;
}

async function appendRelatedSections(dryRun: boolean): Promise<number> {
  const files = await discoverMarkdownFiles();
  const records = buildRegistry(files);
  const changed: string[] = [];

  for (const record of records) {
    if (record.classification !== "canonical") continue;
    const path = join(ROOT, record.path);
    const content = await Deno.readTextFile(path).catch(() => "");
    if (/^##\s+Related\s*$/m.test(content)) continue;
    const related = [
      "",
      "",
      "## Related",
      "",
      `- [Documentation Map](${relativeLink(path, "docs/11-reference/documentation-map.md")})`,
      `- [Contributor Guide](${relativeLink(path, "docs/index.md")})`,
      `- [Repository Documentation Index](${relativeLink(path, "docs/repo-index/index.md")})`,
      "",
    ].join("\n");
    changed.push(record.path);
    if (!dryRun) await Deno.writeTextFile(path, content.trimEnd() + related);
  }

  console.log(
    `[repo-docs] ${
      dryRun ? "would update" : "updated"
    } ${changed.length} canonical docs with missing Related sections`,
  );
  for (const rel of changed.slice(0, 200)) console.log(`  - ${rel}`);
  return 0;
}

function usage(): never {
  console.error(`Usage:
  scripts/docs/repo_docs.ts sync
  scripts/docs/repo_docs.ts enrich-related [--dry-run]
  scripts/docs/repo_docs.ts validate [--internal-strict] [--external-report] [--orphans]
`);
  Deno.exit(2);
}

async function main(): Promise<number> {
  const [command, ...rest] = Deno.args;
  if (command === "sync") return await runSync();
  if (command === "enrich-related") {
    return await appendRelatedSections(rest.includes("--dry-run"));
  }
  if (command === "validate") {
    const flags = new Set(rest);
    if (
      !flags.has("--internal-strict") && !flags.has("--external-report") &&
      !flags.has("--orphans")
    ) {
      console.error(
        "[repo-docs] choose at least one validation mode: --internal-strict, --external-report, --orphans",
      );
      return 2;
    }
    return await validate(flags);
  }
  usage();
}

if (import.meta.main) {
  Deno.exit(await main());
}

#!/usr/bin/env -S deno run -A
import { dirname, fromFileUrl, join, relative, resolve } from "@std/path";

/** Classifies a Markdown document by its publication and discoverability role. */
export type Classification =
  | "canonical"
  | "archive"
  | "decision-record"
  | "entrypoint"
  | "internal-reference"
  | "site-content";

/** Normalized metadata for a Markdown document in the repository registry. */
export interface DocRecord {
  /** Repository-relative path to the Markdown file. */
  path: string;
  /** Publication and discoverability role inferred from the path. */
  classification: Classification;
  /** Canonical documentation page that represents this document's subject. */
  canonical_target: string;
  /** Team or subsystem responsible for maintaining the document. */
  owner: string;
  /** Lifecycle state derived from the document classification. */
  status: string;
}

/** An unresolved internal Markdown link found while scanning a document. */
export interface LinkIssue {
  /** Repository-relative path of the document containing the link. */
  source: string;
  /** One-based source line containing the unresolved link. */
  line: number;
  /** Original link destination after whitespace normalization. */
  href: string;
  /** Human-readable reason the link could not be resolved. */
  message: string;
}

/** A resolved Markdown link between two documents in the registry. */
export interface LinkEdge {
  /** Repository-relative path of the document containing the link. */
  source: string;
  /** Repository-relative path of the resolved destination document. */
  target: string;
  /** Original destination written in the source document. */
  href: string;
  /** One-based source line containing the link. */
  line: number;
}

/** Filesystem locations used by the repository-documentation workflow. */
export interface RepoDocsPaths {
  /** Absolute repository root. */
  root: string;
  /** Absolute `docs/` directory. */
  docs: string;
  /** Directory for generated registry and graph metadata. */
  metadataDir: string;
  /** Directory for generated human-readable reports. */
  reportsDir: string;
  /** Directory for generated navigation pages. */
  indexDir: string;
  /** JSON registry output path. */
  registryPath: string;
  /** JSON Schema output path for registry records. */
  registrySchemaPath: string;
  /** JSON link-graph output path. */
  graphPath: string;
  /** JSON orphan-report output path. */
  orphanJsonPath: string;
  /** JSON record of documentation moves. */
  migrationMapPath: string;
  /** JSON report for scheduled external-link checks. */
  externalReportPath: string;
  /** Text allowlist for canonical documents without inbound links. */
  orphanAllowlistPath: string;
}

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

/**
 * Builds the repository-documentation output paths for a repository root.
 *
 * @param root Absolute path to the repository root.
 * @returns Derived paths for registry, report, and index artifacts.
 */
export function createRepoDocsPaths(root: string): RepoDocsPaths {
  const docs = join(root, "docs");
  const metadataDir = join(docs, "metadata");
  const reportsDir = join(docs, "reports", "docs");
  const indexDir = join(docs, "repo-index");
  return {
    root,
    docs,
    metadataDir,
    reportsDir,
    indexDir,
    registryPath: join(metadataDir, "doc-registry.json"),
    registrySchemaPath: join(metadataDir, "doc-registry.schema.json"),
    graphPath: join(metadataDir, "doc-link-graph.json"),
    orphanJsonPath: join(metadataDir, "doc-orphans.json"),
    migrationMapPath: join(metadataDir, "doc-migration-map.json"),
    externalReportPath: join(metadataDir, "external-links-report.json"),
    orphanAllowlistPath: join(metadataDir, "orphan-allowlist.txt"),
  };
}

function posixRel(root: string, path: string): string {
  return relative(root, path).replaceAll("\\", "/");
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

async function ensureDirs(paths: RepoDocsPaths) {
  for (const dir of [paths.metadataDir, paths.reportsDir, paths.indexDir]) {
    await Deno.mkdir(dir, { recursive: true });
  }
}

/**
 * Recursively yields Markdown files below a directory, excluding generated and
 * dependency directories.
 *
 * @param dir Absolute directory to scan.
 * @returns Absolute paths to discovered Markdown files.
 */
export async function* walkMarkdown(dir: string): AsyncGenerator<string> {
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

/**
 * Discovers repository Markdown files in the supported documentation roots.
 *
 * @param paths Repository-documentation paths that identify the root.
 * @returns Sorted, absolute paths to discovered Markdown files.
 */
export async function discoverMarkdownFiles(
  paths: RepoDocsPaths,
): Promise<string[]> {
  const files = new Set<string>();
  for (const relDir of TOP_LEVEL_MARKDOWN_DIRS) {
    const dir = join(paths.root, relDir);
    if (!await exists(dir)) continue;
    for await (const file of walkMarkdown(dir)) files.add(resolve(file));
  }
  for await (const entry of Deno.readDir(paths.root)) {
    const path = join(paths.root, entry.name);
    if (entry.isFile && entry.name.endsWith(".md")) files.add(resolve(path));
  }
  return [...files].sort((a, b) =>
    posixRel(paths.root, a).localeCompare(posixRel(paths.root, b))
  );
}

/**
 * Classifies a repository-relative Markdown path without reading its contents.
 *
 * @param path Repository-relative Markdown path.
 * @returns The document's publication and discoverability classification.
 */
export function classifyDoc(path: string): Classification {
  if (CANONICAL_DOC_RE.test(path)) return "canonical";
  if (["docs/index.md", "docs/README.md", "docs/SUMMARY.md"].includes(path)) {
    return "canonical";
  }
  if (
    path.startsWith("docs/archive/") || path.startsWith("docs/scratchpad/") ||
    path.startsWith("docs/plans/archive/") || path.startsWith("docs/plan/")
  ) return "archive";
  if (path.startsWith("docs/adr/")) return "decision-record";
  if (path.startsWith("Garazyk/docs-site/src/content/docs/")) {
    return "site-content";
  }
  if (
    ROOT_ENTRYPOINTS.has(path) ||
    (path.startsWith("ADMINUI_") && path.endsWith(".md"))
  ) {
    return "entrypoint";
  }
  return "internal-reference";
}

/**
 * Infers the responsible subsystem from a repository-relative document path.
 *
 * @param path Repository-relative path to classify.
 * @returns Stable owner label used in generated registry records.
 */
export function inferOwner(path: string): string {
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
  if (
    classification === "decision-record" || classification === "site-content"
  ) {
    return "published";
  }
  if (classification === "archive") return "archived";
  return "reference";
}

/**
 * Selects the canonical documentation page for a non-canonical document.
 *
 * @param path Repository-relative document path.
 * @param classification Classification assigned to the document.
 * @returns Repository-relative canonical target path.
 */
export function inferCanonicalTarget(
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
    "ADMINUI_PROJECT_COMPLETE.md":
      "docs/11-reference/admin-ui-documentation.md",
    "ADMINUI_DEPLOYMENT_GUIDE.md":
      "docs/11-reference/admin-ui-documentation.md",
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

/**
 * Builds sorted registry records for discovered Markdown files.
 *
 * @param files Absolute paths to discovered Markdown files.
 * @param root Absolute repository root used to make paths relative.
 * @returns Records sorted by repository-relative path.
 */
export function buildRegistry(files: string[], root: string): DocRecord[] {
  return files.map((file) => {
    const path = posixRel(root, file);
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

async function writeRegistrySchema(paths: RepoDocsPaths) {
  await writeJson(paths.registrySchemaPath, {
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
          enum: [
            "canonical",
            "archive",
            "decision-record",
            "entrypoint",
            "internal-reference",
            "site-content",
          ],
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

/**
 * Resolves an internal Markdown destination relative to its source document.
 *
 * Fragment-only links are intentionally excluded because they do not name a
 * document. Extensionless paths are resolved as Markdown files or directory
 * README/index files.
 *
 * @param source Absolute path of the document containing the link.
 * @param hrefRaw Destination as written in the Markdown link.
 * @param paths Repository-documentation paths used for root-relative links.
 * @returns Absolute destination path, or `null` when the target is unresolved.
 */
export async function resolveInternalTarget(
  source: string,
  hrefRaw: string,
  paths: RepoDocsPaths,
): Promise<string | null> {
  const href = cleanHref(hrefRaw);
  if (!href || href.startsWith("#")) return null;
  const link = removeFragmentAndQuery(href);
  if (!link) return null;

  const candidates: string[] = [];
  if (link.startsWith("/")) {
    const trimmed = link.replace(/^\/+/, "");
    candidates.push(join(paths.root, trimmed), join(paths.docs, trimmed));
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

/** Aggregate counts produced while scanning Markdown links. */
export interface LinkStats {
  /** Number of internal document links inspected. */
  internal: number;
  /** Number of URL-scheme links inspected. */
  external: number;
  /** Number of same-document fragment links skipped. */
  anchor: number;
  /** Number of internal links that could not be resolved. */
  missing: number;
}

/** Complete result of internal and external Markdown link analysis. */
export interface LinkAnalysis {
  /** Resolved links whose targets are registered documents. */
  edges: LinkEdge[];
  /** Unresolved internal links. */
  issues: LinkIssue[];
  /** Resolved destinations grouped by source document. */
  outgoing: Record<string, string[]>;
  /** Aggregate link counts. */
  stats: LinkStats;
  /** Occurrences of each external URL destination. */
  externalCounts: Record<string, number>;
}

/**
 * Parses links in Markdown files and resolves internal document destinations.
 *
 * @param files Absolute paths to scan.
 * @param records Registry records that define graph nodes.
 * @param paths Repository-documentation paths used during resolution.
 * @returns Graph edges, unresolved links, outgoing links, and aggregate counts.
 */
export async function analyzeLinks(
  files: string[],
  records: DocRecord[],
  paths: RepoDocsPaths,
): Promise<LinkAnalysis> {
  const recordPaths = new Set(records.map((record) => record.path));
  const edges: LinkEdge[] = [];
  const issues: LinkIssue[] = [];
  const outgoing: Record<string, string[]> = {};
  const stats = { internal: 0, external: 0, anchor: 0, missing: 0 };
  const externalCounts: Record<string, number> = {};

  for (
    const source of [...files].sort((a, b) =>
      posixRel(paths.root, a).localeCompare(posixRel(paths.root, b))
    )
  ) {
    const rel = posixRel(paths.root, source);
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
      const resolved = await resolveInternalTarget(source, href, paths);
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
      const targetRel = posixRel(paths.root, resolved);
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

async function loadOrphanAllowlist(path: string): Promise<Set<string>> {
  if (!await exists(path)) return new Set();
  const text = await Deno.readTextFile(path);
  return new Set(
    text.split("\n").map((line) => line.trim()).filter((line) =>
      line && !line.startsWith("#")
    ),
  );
}

/** Result of an inbound-link analysis for documents subject to orphan checks. */
export interface OrphanAnalysis {
  /** Canonical documents with no inbound links and no allowlist entry. */
  orphans: string[];
  /** Inbound-link count for every registry document. */
  inbound: Record<string, number>;
}

/**
 * Finds canonical documents without inbound Markdown links, honoring an allowlist.
 *
 * Archive, decision-record, site-content, entrypoint, and source-adjacent
 * documents are discoverable through other mechanisms and are not orphan-check
 * candidates.
 *
 * @param records Registered documents to analyze.
 * @param edges Resolved Markdown link edges between registered documents.
 * @param orphanAllowlistPath Path to newline-delimited exempt document paths.
 * @returns Inbound-link counts for all records and unlinked canonical documents.
 */
export async function computeOrphans(
  records: DocRecord[],
  edges: LinkEdge[],
  orphanAllowlistPath: string,
): Promise<OrphanAnalysis> {
  const inbound: Record<string, number> = Object.fromEntries(
    records.map((record) => [record.path, 0]),
  );
  for (const edge of edges) {
    if (edge.target in inbound) inbound[edge.target]++;
  }
  const allowlist = await loadOrphanAllowlist(orphanAllowlistPath);
  const orphans = records
    .filter((record) =>
      record.classification === "canonical" && inbound[record.path] === 0 &&
      !allowlist.has(record.path)
    )
    .map((record) => record.path)
    .sort();
  return { orphans, inbound };
}

async function writeJson(path: string, payload: unknown) {
  await Deno.mkdir(dirname(path), { recursive: true });
  await Deno.writeTextFile(path, JSON.stringify(payload, null, 2) + "\n");
}

function relativeLink(fromPath: string, toRel: string, root: string): string {
  return relative(dirname(fromPath), join(root, toRel)).replaceAll("\\", "/");
}

async function writeMarkdown(path: string, content: string) {
  await Deno.mkdir(dirname(path), { recursive: true });
  await Deno.writeTextFile(path, content.trimEnd() + "\n");
}

function buildCollection(records: DocRecord[], prefix: string): DocRecord[] {
  return records.filter((record) => record.path.startsWith(prefix));
}

function makeRegistryTable(
  path: string,
  records: DocRecord[],
  root: string,
): string {
  const lines = [
    "| Path | Classification | Canonical Target | Owner | Status |",
    "| --- | --- | --- | --- | --- |",
  ];
  for (const record of records) {
    lines.push(
      `| [${record.path}](${
        relativeLink(path, record.path, root)
      }) | \`${record.classification}\` | [${record.canonical_target}](${
        relativeLink(path, record.canonical_target, root)
      }) | \`${record.owner}\` | \`${record.status}\` |`,
    );
  }
  return lines.join("\n");
}

/**
 * Writes deterministic registry tables, backlink inventory, and index hub pages.
 *
 * @param records Registry records to render.
 * @param inbound Inbound-link counts keyed by repository-relative path.
 * @param edges Resolved document-link graph edges.
 * @param paths Output locations for generated index pages.
 */
export async function generateIndexPages(
  records: DocRecord[],
  inbound: Record<string, number>,
  edges: LinkEdge[],
  paths: RepoDocsPaths,
) {
  const pages: Record<string, DocRecord[]> = {
    "root-entrypoints.md": records.filter((record) =>
      record.classification === "entrypoint"
    ),
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
    const page = join(paths.indexDir, filename);
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
      `${intro.join("\n")}\n${
        makeRegistryTable(page, pageRecords, paths.root)
      }`,
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
          `- [${source}](${
            relativeLink(
              join(paths.indexDir, "backlinks.md"),
              source,
              paths.root,
            )
          })`,
        );
      }
    }
    backlinks.push("");
  }
  await writeMarkdown(
    join(paths.indexDir, "backlinks.md"),
    backlinks.join("\n"),
  );

  await writeMarkdown(
    join(paths.indexDir, "index.md"),
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

async function writeOrphanAllowlistIfMissing(paths: RepoDocsPaths) {
  if (await exists(paths.orphanAllowlistPath)) return;
  await Deno.writeTextFile(
    paths.orphanAllowlistPath,
    "# Paths allowed to have zero inbound markdown links.\n# Keep this list short.\n",
  );
}

async function defaultMigrationMapIfMissing(paths: RepoDocsPaths) {
  if (await exists(paths.migrationMapPath)) return;
  await writeJson(paths.migrationMapPath, {
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
  stats: LinkStats,
  externalCounts: Record<string, number>,
  paths: RepoDocsPaths,
) {
  const { orphans } = await computeOrphans(
    records,
    edges,
    paths.orphanAllowlistPath,
  );
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
  await writeJson(paths.graphPath, payload);
  await writeJson(paths.orphanJsonPath, {
    generated_at: Math.floor(Date.now() / 1000),
    orphans,
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
    join(paths.reportsDir, "link-graph-report.md"),
    report.join("\n"),
  );
}

async function runSync(paths: RepoDocsPaths): Promise<number> {
  await ensureDirs(paths);
  await writeOrphanAllowlistIfMissing(paths);
  await writeRegistrySchema(paths);
  await defaultMigrationMapIfMissing(paths);

  for (let pass = 0; pass < 2; pass++) {
    const files = await discoverMarkdownFiles(paths);
    const records = buildRegistry(files, paths.root);
    const analysis = await analyzeLinks(files, records, paths);
    const { inbound } = await computeOrphans(
      records,
      analysis.edges,
      paths.orphanAllowlistPath,
    );
    await generateIndexPages(records, inbound, analysis.edges, paths);
  }

  const files = await discoverMarkdownFiles(paths);
  const records = buildRegistry(files, paths.root);
  const analysis = await analyzeLinks(files, records, paths);
  const { inbound } = await computeOrphans(
    records,
    analysis.edges,
    paths.orphanAllowlistPath,
  );
  await writeJson(paths.registryPath, records);
  await writeGraphOutputs(
    records,
    analysis.edges,
    analysis.issues,
    inbound,
    analysis.stats,
    analysis.externalCounts,
    paths,
  );

  console.log(
    `[repo-docs] sync complete: ${records.length} docs, ${analysis.edges.length} graph edges`,
  );
  console.log(
    `[repo-docs] registry: ${posixRel(paths.root, paths.registryPath)}`,
  );
  console.log(
    `[repo-docs] index hub: ${
      posixRel(paths.root, join(paths.indexDir, "index.md"))
    }`,
  );
  return 0;
}

async function loadRegistry(paths: RepoDocsPaths): Promise<DocRecord[]> {
  if (!await exists(paths.registryPath)) {
    console.error("[repo-docs] registry missing; run sync first");
    Deno.exit(2);
  }
  return JSON.parse(await Deno.readTextFile(paths.registryPath));
}

async function validateInternalStrict(
  records: DocRecord[],
  paths: RepoDocsPaths,
) {
  const files = records.map((record) => join(paths.root, record.path)).filter(
    (path) => {
      try {
        return Deno.statSync(path).isFile;
      } catch {
        return false;
      }
    },
  );
  return await analyzeLinks(files, records, paths);
}

/** Result of an HTTP probe for one external Markdown link. */
export interface ExternalLinkResult {
  /** `ok`, `error`, or `warning` according to the probe outcome. */
  status: string;
  /** HTTP status code when a response was received. */
  code: number | null;
  /** Response summary or the transport failure message. */
  message: string;
}

/** Persisted report for all unique external links in the registry. */
export interface ExternalLinkReport {
  /** Unix timestamp in seconds when the report was generated. */
  generated_at: number;
  /** Number of distinct external URLs probed. */
  checked: number;
  /** Probe results keyed by external URL. */
  results: Record<string, ExternalLinkResult>;
}

/**
 * Probes each unique external Markdown URL with a bounded HTTP HEAD request.
 *
 * Probe failures are recorded as warnings so scheduled reporting can distinguish
 * unavailable services from confirmed HTTP errors.
 *
 * @param records Registry records whose existing files are scanned.
 * @param paths Paths that identify source files and the report output location.
 * @returns The persisted external-link report.
 */
export async function checkExternalLinks(
  records: DocRecord[],
  paths: RepoDocsPaths,
): Promise<ExternalLinkReport> {
  const files = records.map((record) => join(paths.root, record.path)).filter(
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
  await writeJson(paths.externalReportPath, payload);
  return payload;
}

async function validate(
  flags: Set<string>,
  paths: RepoDocsPaths,
): Promise<number> {
  await ensureDirs(paths);
  const records = await loadRegistry(paths);
  let exitCode = 0;
  let analysis = {
    edges: [] as LinkEdge[],
    issues: [] as LinkIssue[],
    outgoing: {} as Record<string, string[]>,
    stats: { internal: 0, external: 0, anchor: 0, missing: 0 },
    externalCounts: {} as Record<string, number>,
  };

  if (flags.has("--internal-strict") || flags.has("--orphans")) {
    analysis = await validateInternalStrict(records, paths);
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
    const { orphans, inbound } = await computeOrphans(
      records,
      analysis.edges,
      paths.orphanAllowlistPath,
    );
    await writeGraphOutputs(
      records,
      analysis.edges,
      analysis.issues,
      inbound,
      analysis.stats,
      analysis.externalCounts,
      paths,
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
    const report = await checkExternalLinks(records, paths);
    const bad = Object.values(report.results).filter((info) =>
      ["error", "warning"].includes(info.status)
    );
    console.log(
      `[repo-docs] external report complete: checked=${report.checked} issues=${bad.length}`,
    );
  }
  return exitCode;
}

async function appendRelatedSections(
  dryRun: boolean,
  paths: RepoDocsPaths,
): Promise<number> {
  const files = await discoverMarkdownFiles(paths);
  const records = buildRegistry(files, paths.root);
  const changed: string[] = [];

  for (const record of records) {
    if (record.classification !== "canonical") continue;
    const path = join(paths.root, record.path);
    const content = await Deno.readTextFile(path).catch(() => "");
    if (/^##\s+Related\s*$/m.test(content)) continue;
    const related = [
      "",
      "",
      "## Related",
      "",
      `- [Documentation Map](${
        relativeLink(path, "docs/11-reference/documentation-map.md", paths.root)
      })`,
      `- [Contributor Guide](${
        relativeLink(path, "docs/index.md", paths.root)
      })`,
      `- [Repository Documentation Index](${
        relativeLink(path, "docs/repo-index/index.md", paths.root)
      })`,
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

/**
 * Runs the repository-documentation CLI using `Deno.args`.
 *
 * Supported commands are `sync`, `enrich-related`, and `validate`; validation
 * requires one or more explicit modes to avoid accidental network checks.
 *
 * @returns Process exit code for the selected command.
 */
export async function main(): Promise<number> {
  const defaultRoot = resolve(dirname(fromFileUrl(import.meta.url)), "../..");
  const paths = createRepoDocsPaths(defaultRoot);
  const [command, ...rest] = Deno.args;
  if (command === "sync") return await runSync(paths);
  if (command === "enrich-related") {
    return await appendRelatedSections(rest.includes("--dry-run"), paths);
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
    return await validate(flags, paths);
  }
  usage();
}

if (import.meta.main) {
  Deno.exit(await main());
}

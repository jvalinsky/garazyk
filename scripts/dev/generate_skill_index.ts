#!/usr/bin/env -S deno run --allow-read --allow-write

/**
 * Generates the project skill index from `.agents/skills/*\/SKILL.md` frontmatter.
 *
 * Output:
 *   .agents/skills/INDEX.md
 *
 * AGENTS.md links to this file instead of carrying a hand-maintained table,
 * which drifted to 25 of 64 skills before this generator existed.
 *
 * Usage:
 *   deno run -A scripts/dev/generate_skill_index.ts          # regenerate
 *   deno run -A scripts/dev/generate_skill_index.ts --check  # drift check (CI)
 */

import { dirname, fromFileUrl, join } from "@std/path";

const SCRIPT_DIR = dirname(fromFileUrl(import.meta.url));
const REPO_ROOT = dirname(dirname(SCRIPT_DIR));
const SKILLS_DIR = join(REPO_ROOT, ".agents", "skills");
const OUT_PATH = join(SKILLS_DIR, "INDEX.md");

/**
 * Category assignment, most specific rule first. A skill that matches nothing
 * lands in "Other" rather than being dropped, so a new skill is always visible
 * even before someone classifies it.
 */
const CATEGORIES: { title: string; match: (name: string) => boolean }[] = [
  {
    title: "Garazyk services and packages",
    match: (n) => n.startsWith("garazyk-"),
  },
  {
    title: "Objective-C and platform",
    match: (n) =>
      n.startsWith("objc-") || n.startsWith("better-code-") ||
      n === "gnustep-compat" || n === "debugging-objc-crashes",
  },
  {
    title: "Database and SQL",
    match: (n) => n.startsWith("sqlite") || n.startsWith("sql-"),
  },
  {
    title: "AT Protocol and scenarios",
    match: (n) =>
      n.startsWith("atproto-") || n.startsWith("adding-scenario") ||
      n.startsWith("agent-scenario") || n.startsWith("designing-atproto") ||
      n.startsWith("testing-atproto"),
  },
  {
    title: "Audits and review",
    match: (n) =>
      n.endsWith("-audit") || n.includes("audit") || n === "slop-detector",
  },
  { title: "TUI", match: (n) => n.startsWith("tui-") },
  {
    title: "Decision graph and planning",
    match: (n) =>
      n.includes("deciduous") || n === "pulse" || n === "narratives" ||
      n === "archaeology",
  },
  {
    title: "Writing and documentation",
    match: (n) =>
      n === "technical-writer" || n === "deslop" || n === "tsdoc-standards" ||
      n === "rewriting-code-comments" || n === "expand-md-topic",
  },
  {
    title: "Languages and general tooling",
    match: (n) =>
      n === "typescript-expert" || n === "regex-expert" ||
      n === "wasm-expert" || n === "professional-bash-scripting" ||
      n === "web-search" || n === "prompt-engineer" ||
      n === "researcher-hand-skill",
  },
  {
    title: "Frontend",
    match: (n) => n === "impeccable" || n === "web-ui-audit",
  },
];

interface Skill {
  name: string;
  summary: string;
}

/** Reads `name` and `description` out of a SKILL.md YAML frontmatter block. */
function parseFrontmatter(
  text: string,
): { name?: string; description?: string } {
  if (!text.startsWith("---")) return {};
  const end = text.indexOf("\n---", 3);
  if (end === -1) return {};
  const block = text.slice(4, end);

  const out: Record<string, string> = {};
  let key: string | null = null;
  for (const line of block.split("\n")) {
    const m = line.match(/^([a-zA-Z_-]+):\s*(.*)$/);
    if (m) {
      key = m[1];
      out[key] = m[2].trim();
    } else if (key && /^\s+\S/.test(line)) {
      // YAML folded continuation line.
      out[key] = `${out[key]} ${line.trim()}`.trim();
    } else {
      key = null;
    }
  }
  return { name: unquote(out.name), description: unquote(out.description) };
}

/** Strips the surrounding quotes YAML scalars may carry. */
function unquote(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;
  const trimmed = value.trim();
  const quoted = (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"));
  return quoted && trimmed.length >= 2 ? trimmed.slice(1, -1) : trimmed;
}

/**
 * Trims a description to its first sentence, capped at 160 characters. Full
 * text stays in the skill file; the index only needs the triggering signal.
 */
function summarize(description: string): string {
  const flat = description.replace(/\s+/g, " ").trim();
  const firstSentence = flat.match(/^.*?[.!?](?=\s|$)/)?.[0] ?? flat;
  const chosen = firstSentence.length > 20 ? firstSentence : flat;
  if (chosen.length <= 160) return chosen;
  return `${chosen.slice(0, 157).trimEnd()}…`;
}

function categorize(name: string): string {
  return CATEGORIES.find((c) => c.match(name))?.title ?? "Other";
}

async function collectSkills(): Promise<Skill[]> {
  const skills: Skill[] = [];
  const problems: string[] = [];

  for await (const entry of Deno.readDir(SKILLS_DIR)) {
    if (!entry.isDirectory) continue;
    const skillPath = join(SKILLS_DIR, entry.name, "SKILL.md");
    let text: string;
    try {
      text = await Deno.readTextFile(skillPath);
    } catch {
      problems.push(`${entry.name}: no SKILL.md`);
      continue;
    }
    const { name, description } = parseFrontmatter(text);
    if (!description) {
      problems.push(
        `${entry.name}: SKILL.md has no \`description:\` frontmatter, so no ` +
          `client can match it to a task`,
      );
      continue;
    }
    if (name && name !== entry.name) {
      problems.push(
        `${entry.name}: frontmatter name is \`${name}\`; directory and name must match`,
      );
    }
    skills.push({ name: entry.name, summary: summarize(description) });
  }

  if (problems.length > 0) {
    console.error("Skill definition problems:");
    for (const p of problems) console.error(`  - ${p}`);
    Deno.exit(1);
  }

  skills.sort((a, b) => a.name.localeCompare(b.name));
  return skills;
}

function render(skills: Skill[]): string {
  const grouped = new Map<string, Skill[]>();
  for (const skill of skills) {
    const category = categorize(skill.name);
    const bucket = grouped.get(category) ?? [];
    bucket.push(skill);
    grouped.set(category, bucket);
  }

  // Declared order first, then "Other" last so unclassified skills stand out.
  const order = [...CATEGORIES.map((c) => c.title), "Other"];

  const lines: string[] = [
    "<!-- Generated by scripts/dev/generate_skill_index.ts. Do not edit by hand. -->",
    "",
    "---",
    "title: Project Skill Index",
    "---",
    "",
    "# Project Skill Index",
    "",
    `${skills.length} skills live in \`.agents/skills/\`. Load one with the client's`,
    "skill tool when a task matches its description; each `SKILL.md` holds the full",
    "text. Regenerate this file with:",
    "",
    "```bash",
    "deno run -A scripts/dev/generate_skill_index.ts",
    "```",
    "",
  ];

  for (const category of order) {
    const bucket = grouped.get(category);
    if (!bucket || bucket.length === 0) continue;
    lines.push(`## ${category}`, "");
    lines.push("| Skill | Use for |", "| --- | --- |");
    for (const skill of bucket) {
      lines.push(`| \`${skill.name}\` | ${skill.summary} |`);
    }
    lines.push("");
  }

  return lines.join("\n");
}

async function main(args: string[]) {
  const checkMode = args.includes("--check");
  const skills = await collectSkills();
  const rendered = render(skills);

  if (checkMode) {
    let existing = "";
    try {
      existing = await Deno.readTextFile(OUT_PATH);
    } catch {
      console.error(
        `Missing ${OUT_PATH}. Run: deno run -A scripts/dev/generate_skill_index.ts`,
      );
      Deno.exit(1);
    }
    if (existing !== rendered) {
      console.error(
        `${OUT_PATH} is out of date (${skills.length} skills on disk). ` +
          `Run: deno run -A scripts/dev/generate_skill_index.ts`,
      );
      Deno.exit(1);
    }
    console.log(`Skill index up to date (${skills.length} skills).`);
    return;
  }

  await Deno.writeTextFile(OUT_PATH, rendered);
  console.log(`Wrote ${OUT_PATH} (${skills.length} skills).`);
}

await main(Deno.args);

/** Tests for narzedzia/repo_docs.ts — classifyDoc, inferOwner, inferCanonicalTarget. @module repo_docs_test */

import { assertEquals } from "@std/assert";
import {
  classifyDoc,
  createRepoDocsPaths,
  inferCanonicalTarget,
  inferOwner,
} from "./repo_docs.ts";

// ── classifyDoc ─────────────────────────────────────────────────────────

Deno.test("classifyDoc: canonical for numbered docs directory", () => {
  assertEquals(classifyDoc("docs/01-getting-started/setup.md"), "canonical");
  assertEquals(classifyDoc("docs/12-advanced/topic.md"), "canonical");
});

Deno.test("classifyDoc: canonical for index/README/SUMMARY", () => {
  assertEquals(classifyDoc("docs/index.md"), "canonical");
  assertEquals(classifyDoc("docs/README.md"), "canonical");
  assertEquals(classifyDoc("docs/SUMMARY.md"), "canonical");
});

Deno.test("classifyDoc: archive for archive/scratchpad/plans paths", () => {
  assertEquals(classifyDoc("docs/archive/old.md"), "archive");
  assertEquals(classifyDoc("docs/scratchpad/draft.md"), "archive");
  assertEquals(classifyDoc("docs/plans/archive/retired.md"), "archive");
  assertEquals(classifyDoc("docs/plan/draft.md"), "archive");
});

Deno.test("classifyDoc: entrypoint for root-level known files", () => {
  assertEquals(classifyDoc("README.md"), "entrypoint");
  assertEquals(classifyDoc("BUILD.md"), "entrypoint");
  assertEquals(classifyDoc("CONTRIBUTING.md"), "entrypoint");
  assertEquals(classifyDoc("AGENTS.md"), "entrypoint");
  assertEquals(classifyDoc("DOCUMENTATION.md"), "entrypoint");
});

Deno.test("classifyDoc: entrypoint for ADMINUI_ prefixed files", () => {
  assertEquals(classifyDoc("ADMINUI_START_HERE.md"), "entrypoint");
  assertEquals(classifyDoc("ADMINUI_QUICKSTART.md"), "entrypoint");
});

Deno.test("classifyDoc: internal-reference for everything else", () => {
  assertEquals(classifyDoc("docs/guides/some-guide.md"), "internal-reference");
  assertEquals(classifyDoc("Garazyk/Sources/README.md"), "internal-reference");
  assertEquals(classifyDoc("tooling/notes.md"), "internal-reference");
});

// ── inferOwner ──────────────────────────────────────────────────────────

Deno.test("inferOwner: docs paths map to correct owners", () => {
  assertEquals(inferOwner("docs/security/audit.md"), "security");
  assertEquals(inferOwner("docs/tests/test-guide.md"), "quality");
  assertEquals(inferOwner("docs/plans/roadmap.md"), "planning");
  assertEquals(inferOwner("docs/index.md"), "docs");
  assertEquals(inferOwner("docs/guides/intro.md"), "docs");
});

Deno.test("inferOwner: Garazyk paths map to core/admin", () => {
  assertEquals(inferOwner("Garazyk/Sources/Admin/UI.md"), "admin");
  assertEquals(inferOwner("Garazyk/Sources/PDS/Store.m"), "core");
  assertEquals(inferOwner("Garazyk/Sources/Auth/Login.m"), "core");
});

Deno.test("inferOwner: tooling and skills paths", () => {
  assertEquals(inferOwner("tooling/notes.md"), "tooling");
  assertEquals(inferOwner("skills/some-skill.md"), "skills");
  assertEquals(inferOwner("scripts/deploy.sh"), "tooling");
});

Deno.test("inferOwner: examples and fallback", () => {
  assertEquals(inferOwner("examples/tutorial.md"), "docs");
  assertEquals(inferOwner("unknown/path.md"), "docs");
});

// ── inferCanonicalTarget ────────────────────────────────────────────────

Deno.test("inferCanonicalTarget: canonical files return themselves", () => {
  assertEquals(
    inferCanonicalTarget("docs/01-getting-started/setup.md", "canonical"),
    "docs/01-getting-started/setup.md",
  );
});

Deno.test("inferCanonicalTarget: root entrypoints map to known targets", () => {
  assertEquals(inferCanonicalTarget("README.md", "entrypoint"), "docs/index.md");
  assertEquals(
    inferCanonicalTarget("BUILD.md", "entrypoint"),
    "docs/01-getting-started/setup.md",
  );
  assertEquals(
    inferCanonicalTarget("AGENTS.md", "entrypoint"),
    "docs/11-reference/documentation-map.md",
  );
  assertEquals(
    inferCanonicalTarget("ADMINUI_START_HERE.md", "entrypoint"),
    "docs/11-reference/admin-ui-documentation.md",
  );
});

Deno.test("inferCanonicalTarget: security paths target security guide", () => {
  assertEquals(
    inferCanonicalTarget("docs/security/auth.md", "internal-reference"),
    "docs/11-reference/security-audit-guide.md",
  );
});

Deno.test("inferCanonicalTarget: test paths target testing map", () => {
  assertEquals(
    inferCanonicalTarget("docs/tests/e2e.md", "internal-reference"),
    "docs/11-reference/testing-map.md",
  );
});

Deno.test("inferCanonicalTarget: Garazyk source targets admin or source docs", () => {
  assertEquals(
    inferCanonicalTarget("Garazyk/Sources/Admin/UI.md", "internal-reference"),
    "docs/11-reference/admin-ui-documentation.md",
  );
  assertEquals(
    inferCanonicalTarget("Garazyk/Sources/PDS/Store.m", "internal-reference"),
    "docs/11-reference/source-adjacent-documentation.md",
  );
});

Deno.test("inferCanonicalTarget: tooling/scripts/skills target tooling docs", () => {
  const expected = "docs/11-reference/tooling-and-skills-documentation.md";
  assertEquals(
    inferCanonicalTarget("tooling/something.md", "internal-reference"),
    expected,
  );
  assertEquals(
    inferCanonicalTarget("scripts/deploy.sh", "internal-reference"),
    expected,
  );
  assertEquals(
    inferCanonicalTarget("skills/some-skill.md", "internal-reference"),
    expected,
  );
});

Deno.test("inferCanonicalTarget: examples target tutorials", () => {
  assertEquals(
    inferCanonicalTarget("examples/tutorial.md", "archive"),
    "docs/10-tutorials/index.md",
  );
});

Deno.test("inferCanonicalTarget: plan/archive/scratchpad target planning archive", () => {
  const expected = "docs/archive/planning/README.md";
  assertEquals(
    inferCanonicalTarget("docs/plans/roadmap.md", "archive"),
    expected,
  );
  assertEquals(
    inferCanonicalTarget("docs/plan/draft.md", "archive"),
    expected,
  );
  assertEquals(
    inferCanonicalTarget("docs/scratchpad/notes.md", "archive"),
    expected,
  );
});

Deno.test("inferCanonicalTarget: unknown path defaults to docs/index.md", () => {
  assertEquals(
    inferCanonicalTarget("unknown/file.md", "internal-reference"),
    "docs/index.md",
  );
});

// ── createRepoDocsPaths ─────────────────────────────────────────────────

Deno.test("createRepoDocsPaths: builds correct path structure", () => {
  const paths = createRepoDocsPaths("/project");

  assertEquals(paths.root, "/project");
  assertEquals(paths.docs, "/project/docs");
  assertEquals(paths.metadataDir, "/project/docs/metadata");
  assertEquals(paths.registryPath, "/project/docs/metadata/doc-registry.json");
  assertEquals(paths.graphPath, "/project/docs/metadata/doc-link-graph.json");
  assertEquals(
    paths.indexDir,
    "/project/docs/repo-index",
  );
});

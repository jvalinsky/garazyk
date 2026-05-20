import { assert, assertEquals } from "@std/assert";
import {
  addCounts,
  classifyDoc,
  countDocumentation,
  emptyCounts,
  inferCanonicalTarget,
  inferOwner,
  inferStatus,
  missingCounts,
  pct,
  summarize,
  subsystemForPath,
} from "./doc_coverage.ts";

Deno.test("emptyCounts initializes every bucket to zero", () => {
  const counts = emptyCounts();

  assertEquals(counts, {
    classes: { total: 0, documented: 0 },
    methods: { total: 0, documented: 0 },
    properties: { total: 0, documented: 0 },
    enums: { total: 0, documented: 0 },
    categories: { total: 0, documented: 0 },
    protocols: { total: 0, documented: 0 },
  });
});

Deno.test("addCounts mutates the target by summing matching buckets", () => {
  const target = emptyCounts();
  target.classes.total = 1;
  target.methods.documented = 1;

  const source = emptyCounts();
  source.classes.total = 2;
  source.classes.documented = 1;
  source.methods.total = 3;
  source.methods.documented = 2;

  addCounts(target, source);

  assertEquals(target.classes, { total: 3, documented: 1 });
  assertEquals(target.methods, { total: 3, documented: 3 });
  assertEquals(source.classes, { total: 2, documented: 1 });
});

Deno.test("missingCounts returns the undocumented remainder per bucket", () => {
  const counts = emptyCounts();
  counts.classes.total = 5;
  counts.classes.documented = 2;
  counts.methods.total = 1;
  counts.methods.documented = 0;
  counts.properties.total = 4;
  counts.properties.documented = 4;

  assertEquals(missingCounts(counts), {
    classes: 3,
    methods: 1,
    properties: 0,
    enums: 0,
    categories: 0,
    protocols: 0,
  });
});

Deno.test("pct returns 100 when nothing is counted", () => {
  assertEquals(pct(0, 0), 100);
});

Deno.test("pct floors fractional percentages", () => {
  assertEquals(pct(3, 1), 33);
  assertEquals(pct(8, 7), 87);
});

Deno.test("summarize aggregates totals and documented counts across buckets", () => {
  const counts = emptyCounts();
  counts.classes.total = 2;
  counts.classes.documented = 1;
  counts.methods.total = 1;
  counts.methods.documented = 1;
  counts.properties.total = 3;
  counts.properties.documented = 2;

  assertEquals(summarize(counts), {
    total: 6,
    documented: 4,
    percent: 66,
  });
});

Deno.test("subsystemForPath maps the primary Garazyk source folders", () => {
  assert(subsystemForPath("./Garazyk/Sources/Core/Foo.h") === "Core");
  assertEquals(subsystemForPath("./Garazyk/Sources/Database/Foo.h"), "Database");
  assertEquals(subsystemForPath("./Garazyk/Sources/Blob/Foo.h"), "Blob");
  assertEquals(subsystemForPath("./Garazyk/Sources/Chat/Foo.h"), "Chat");
  assertEquals(subsystemForPath("./Garazyk/Sources/AppView/Foo.h"), "AppView");
  assertEquals(subsystemForPath("./Garazyk/Sources/Services/Foo.h"), "Services");
  assertEquals(
    subsystemForPath("./Garazyk/Sources/AdminUIServer/Foo.h"),
    "AdminUIServer",
  );
});

Deno.test("subsystemForPath handles special subfolders and the fallback case", () => {
  assertEquals(subsystemForPath("Garazyk/Sources/Mikrus/Foo.h"), "Services");
  assertEquals(
    subsystemForPath("Garazyk/Sources/Registration/Foo.h"),
    "Services",
  );
  assertEquals(subsystemForPath("Garazyk/Sources/PLC/Foo.h"), "Core");
  assertEquals(subsystemForPath("Garazyk/Sources/Sync/Foo.h"), "Core");
  assertEquals(subsystemForPath("Garazyk/Sources/Security/Foo.h"), "Core");
  assertEquals(subsystemForPath("Garazyk/Sources/Repository/Foo.h"), "Core");
  assertEquals(subsystemForPath("Garazyk/Sources/Video/Foo.h"), "Services");
  assertEquals(subsystemForPath("Garazyk/Sources/Elsewhere/Foo.h"), "Other");
});

Deno.test("classifyDoc marks archive and scratchpad docs as archived", () => {
  assertEquals(classifyDoc("docs/archive/old-plan.md"), "archive");
  assertEquals(classifyDoc("docs/scratchpad/notes.md"), "archive");
});

Deno.test("classifyDoc treats docs paths as canonical even when they end with README.md", () => {
  assertEquals(classifyDoc("docs/guides/getting-started.md"), "canonical");
  assertEquals(classifyDoc("docs/README.md"), "canonical");
});

Deno.test("classifyDoc treats non-doc README files as entrypoints", () => {
  assertEquals(classifyDoc("README.md"), "entrypoint");
  assertEquals(classifyDoc("packages/narzedzia/README.md"), "entrypoint");
});

Deno.test("classifyDoc leaves ordinary non-doc files as internal references", () => {
  assertEquals(classifyDoc("src/notes.md"), "internal-reference");
  assertEquals(classifyDoc("Garazyk/Sources/Core/Foo.h"), "internal-reference");
});

Deno.test("inferOwner routes docs subtrees to the expected owners", () => {
  assertEquals(inferOwner("docs/security/audit.md"), "security");
  assertEquals(inferOwner("docs/tests/coverage.md"), "quality");
  assertEquals(inferOwner("docs/plans/roadmap.md"), "planning");
  assertEquals(inferOwner("docs/reference/index.md"), "docs");
  assertEquals(inferOwner("docs/index.md"), "docs");
});

Deno.test("inferOwner routes source, tooling, skills, examples, and admin paths", () => {
  assertEquals(inferOwner("Garazyk/Sources/Admin/Panel.m"), "admin");
  assertEquals(inferOwner("Garazyk/Sources/Core/Thing.m"), "core");
  assertEquals(inferOwner("tooling/build.ts"), "tooling");
  assertEquals(inferOwner("scripts/generate.ts"), "tooling");
  assertEquals(inferOwner("skills/search/SKILL.md"), "skills");
  assertEquals(inferOwner("examples/demo.md"), "docs");
  assertEquals(inferOwner("misc/other.md"), "docs");
});

Deno.test("inferStatus maps classifications to lifecycle states", () => {
  assertEquals(inferStatus("canonical"), "active");
  assertEquals(inferStatus("entrypoint"), "active");
  assertEquals(inferStatus("archive"), "archived");
  assertEquals(inferStatus("internal-reference"), "reference");
});

Deno.test("inferCanonicalTarget preserves canonical docs and resolves explicit entrypoints", () => {
  assertEquals(
    inferCanonicalTarget("docs/guides/intro.md", "canonical"),
    "docs/guides/intro.md",
  );
  assertEquals(inferCanonicalTarget("README.md", "entrypoint"), "docs/index.md");
  assertEquals(
    inferCanonicalTarget("BUILD.md", "entrypoint"),
    "docs/01-getting-started/setup.md",
  );
  assertEquals(
    inferCanonicalTarget("AGENTS.md", "entrypoint"),
    "docs/11-reference/documentation-map.md",
  );
});

Deno.test("inferCanonicalTarget maps docs subtrees and source-adjacent files", () => {
  assertEquals(
    inferCanonicalTarget("docs/security/audit.md", "archive"),
    "docs/11-reference/security-audit-guide.md",
  );
  assertEquals(
    inferCanonicalTarget("docs/tests/coverage.md", "archive"),
    "docs/11-reference/testing-map.md",
  );
  assertEquals(
    inferCanonicalTarget("docs/plans/roadmap.md", "archive"),
    "docs/archive/planning/README.md",
  );
  assertEquals(
    inferCanonicalTarget("docs/architecture/overview.md", "reference"),
    "docs/01-getting-started/architecture-overview.md",
  );
  assertEquals(
    inferCanonicalTarget("Garazyk/Sources/Admin/Panel.m", "reference"),
    "docs/11-reference/admin-ui-documentation.md",
  );
  assertEquals(
    inferCanonicalTarget("Garazyk/Sources/Core/Thing.m", "reference"),
    "docs/11-reference/source-adjacent-documentation.md",
  );
  assertEquals(
    inferCanonicalTarget("skills/search/SKILL.md", "reference"),
    "docs/11-reference/tooling-and-skills-documentation.md",
  );
  assertEquals(
    inferCanonicalTarget("examples/demo.md", "reference"),
    "docs/10-tutorials/index.md",
  );
});

Deno.test("countDocumentation counts all documented symbol kinds", () => {
  const content = [
    "/** @abstract */",
    "@interface AbstractClass : NSObject",
    "/** @abstract */",
    "@interface AbstractClass(Category)",
    "/** @abstract */",
    "@protocol AbstractProtocol",
    "/** @abstract */",
    "typedef NS_ENUM(NSInteger, AbstractEnum) {",
    "  AbstractEnumValue = 0,",
    "};",
    "/**",
    "method docs",
    "*/",
    "- (void)documentedMethod;",
    "/** @abstract */",
    "@property(nonatomic, strong) id name;",
  ].join("\n");

  const counts = countDocumentation(content);

  assertEquals(counts.classes, { total: 1, documented: 1 });
  assertEquals(counts.categories, { total: 1, documented: 1 });
  assertEquals(counts.protocols, { total: 1, documented: 1 });
  assertEquals(counts.enums, { total: 1, documented: 1 });
  assertEquals(counts.methods, { total: 1, documented: 1 });
  assertEquals(counts.properties, { total: 1, documented: 1 });
});

Deno.test("countDocumentation documents methods exactly 10 lines after a doc block", () => {
  const content = [
    "/**",
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
    "line 6",
    "line 7",
    "line 8",
    "line 9",
    "- (void)withinWindow;",
    "- (void)outsideWindow;",
  ].join("\n");

  const counts = countDocumentation(content);

  assertEquals(counts.methods, { total: 2, documented: 1 });
});

Deno.test("countDocumentation documents properties when a doc block is within the 5-line lookback window", () => {
  const content = [
    "/**",
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "@property(nonatomic, strong) id withinWindow;",
    "line 6",
    "line 7",
    "line 8",
    "line 9",
    "line 10",
    "@property(nonatomic, strong) id outsideWindow;",
  ].join("\n");

  const counts = countDocumentation(content);

  assertEquals(counts.properties, { total: 2, documented: 1 });
});

Deno.test("countDocumentation leaves unmarked symbols undocumented", () => {
  const content = [
    "@interface PlainClass : NSObject",
    "@interface PlainClass(Category)",
    "@protocol PlainProtocol",
    "typedef NS_ENUM(NSInteger, PlainEnum) {",
    "  PlainEnumValue = 0,",
    "};",
    "@property(nonatomic, copy) NSString *name;",
    "- (void)plainMethod;",
  ].join("\n");

  const counts = countDocumentation(content);

  assertEquals(counts.classes, { total: 1, documented: 0 });
  assertEquals(counts.categories, { total: 1, documented: 0 });
  assertEquals(counts.protocols, { total: 1, documented: 0 });
  assertEquals(counts.enums, { total: 1, documented: 0 });
  assertEquals(counts.properties, { total: 1, documented: 0 });
  assertEquals(counts.methods, { total: 1, documented: 0 });
});

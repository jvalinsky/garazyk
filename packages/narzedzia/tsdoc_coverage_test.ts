import { assert, assertEquals } from "@std/assert";
import {
  buildReport,
  type CoverageItem,
  type SymbolKind,
} from "./tsdoc_coverage.ts";

const allKinds: SymbolKind[] = [
  "class",
  "interface",
  "type",
  "enum",
  "function",
  "variable",
  "classMethod",
  "classProperty",
  "interfaceProperty",
  "typeParam",
];

function mkItem(
  kind: SymbolKind,
  symbol: string,
  file: string,
  line: number,
  documented: boolean,
): CoverageItem {
  return { kind, symbol, file, line, documented };
}

function bucket(documented: number, total: number) {
  return {
    documented,
    total,
    percent: total === 0 ? 100 : Number(((documented / total) * 100).toFixed(2)),
  };
}

Deno.test("buildReport returns empty-but-complete buckets for no items", () => {
  const warnings = ["warn-one", "warn-two"];
  const report = buildReport([], warnings);

  assertEquals(report.overall, bucket(0, 0));
  assertEquals(Object.keys(report.byKind), allKinds);
  for (const kind of allKinds) {
    assertEquals(report.byKind[kind], bucket(0, 0));
  }
  assertEquals(report.byFile, {});
  assertEquals(report.missing, []);
  assert(report.warnings === warnings);
});

Deno.test("buildReport reports full coverage when every item is documented", () => {
  const items = [
    mkItem("class", "ExampleClass", "src/example.ts", 2, true),
    mkItem("function", "doThing", "src/example.ts", 8, true),
    mkItem("enum", "ExampleEnum", "src/example.ts", 15, true),
  ];

  const report = buildReport(items, []);

  assertEquals(report.overall, bucket(3, 3));
  assertEquals(report.byFile["src/example.ts"], bucket(3, 3));
  assertEquals(report.byKind.class, bucket(1, 1));
  assertEquals(report.byKind.function, bucket(1, 1));
  assertEquals(report.byKind.enum, bucket(1, 1));
  assertEquals(report.missing, []);
});

Deno.test("buildReport reports zero coverage when every item is undocumented", () => {
  const items = [
    mkItem("function", "zeta", "src/b.ts", 9, false),
    mkItem("class", "Alpha", "src/a.ts", 4, false),
    mkItem("enum", "Mode", "src/a.ts", 1, false),
  ];

  const report = buildReport(items, []);

  assertEquals(report.overall, bucket(0, 3));
  assertEquals(report.byKind.function, bucket(0, 1));
  assertEquals(report.byKind.class, bucket(0, 1));
  assertEquals(report.byKind.enum, bucket(0, 1));
  assertEquals(
    report.missing,
    [
      mkItem("enum", "Mode", "src/a.ts", 1, false),
      mkItem("class", "Alpha", "src/a.ts", 4, false),
      mkItem("function", "zeta", "src/b.ts", 9, false),
    ],
  );
});

Deno.test("buildReport mixes documented and undocumented items in the totals", () => {
  const items = [
    mkItem("class", "DocumentedClass", "src/mixed.ts", 2, true),
    mkItem("class", "UndocumentedClass", "src/mixed.ts", 12, false),
    mkItem("variable", "documentedValue", "src/mixed.ts", 20, true),
    mkItem("variable", "missingValue", "src/mixed.ts", 30, false),
  ];

  const report = buildReport(items, []);

  assertEquals(report.overall, bucket(2, 4));
  assertEquals(report.byKind.class, bucket(1, 2));
  assertEquals(report.byKind.variable, bucket(1, 2));
  assertEquals(report.byFile["src/mixed.ts"], bucket(2, 4));
  assertEquals(report.missing.length, 2);
});

Deno.test("buildReport buckets every supported symbol kind", () => {
  const items = [
    mkItem("class", "Widget", "src/kinds.ts", 1, true),
    mkItem("interface", "WidgetProps", "src/kinds.ts", 2, true),
    mkItem("type", "WidgetState", "src/kinds.ts", 3, true),
    mkItem("enum", "WidgetMode", "src/kinds.ts", 4, true),
    mkItem("function", "renderWidget", "src/kinds.ts", 5, true),
    mkItem("variable", "DEFAULT_WIDGET", "src/kinds.ts", 6, true),
    mkItem("classMethod", "Widget.render", "src/kinds.ts", 7, true),
    mkItem("classProperty", "Widget.id", "src/kinds.ts", 8, true),
    mkItem("interfaceProperty", "WidgetProps.name", "src/kinds.ts", 9, true),
    mkItem("typeParam", "Widget<T>", "src/kinds.ts", 10, true),
  ];

  const report = buildReport(items, []);

  assertEquals(report.overall, bucket(10, 10));
  for (const kind of allKinds) {
    assertEquals(report.byKind[kind], bucket(1, 1));
  }
  assertEquals(report.missing, []);
});

Deno.test("buildReport groups totals by file and sorts file buckets lexicographically", () => {
  const items = [
    mkItem("function", "beta", "src/z.ts", 2, true),
    mkItem("class", "alpha", "src/a.ts", 3, false),
    mkItem("type", "Config", "src/m.ts", 4, true),
    mkItem("variable", "gamma", "src/a.ts", 8, false),
  ];

  const report = buildReport(items, []);

  assertEquals(Object.keys(report.byFile), ["src/a.ts", "src/m.ts", "src/z.ts"]);
  assertEquals(report.byFile["src/a.ts"], bucket(0, 2));
  assertEquals(report.byFile["src/m.ts"], bucket(1, 1));
  assertEquals(report.byFile["src/z.ts"], bucket(1, 1));
});

Deno.test("buildReport keeps missing items in the report with their full item data", () => {
  const items = [
    mkItem("function", "documented", "src/keep.ts", 1, true),
    mkItem("function", "missing", "src/keep.ts", 2, false),
  ];

  const report = buildReport(items, []);

  assertEquals(report.missing, [mkItem("function", "missing", "src/keep.ts", 2, false)]);
  assertEquals(report.missing[0], items[1]);
});

Deno.test("buildReport passes warnings through unchanged", () => {
  const warnings = ["first warning", "second warning"];
  const report = buildReport([], warnings);

  assert(report.warnings === warnings);
  assertEquals(report.warnings, warnings);
});

Deno.test("buildReport sorts missing items by file, line, and symbol", () => {
  const items = [
    mkItem("function", "zeta", "src/b.ts", 20, false),
    mkItem("class", "gamma", "src/a.ts", 30, false),
    mkItem("function", "beta", "src/a.ts", 10, false),
    mkItem("function", "alpha", "src/a.ts", 10, false),
  ];

  const report = buildReport(items, []);

  assertEquals(report.missing, [
    mkItem("function", "alpha", "src/a.ts", 10, false),
    mkItem("function", "beta", "src/a.ts", 10, false),
    mkItem("class", "gamma", "src/a.ts", 30, false),
    mkItem("function", "zeta", "src/b.ts", 20, false),
  ]);
});

Deno.test("buildReport exposes zero-count buckets for kinds that do not appear", () => {
  const report = buildReport([
    mkItem("function", "onlyOne", "src/only.ts", 1, true),
  ], []);

  assertEquals(report.byKind.function, bucket(1, 1));
  assertEquals(report.byKind.class, bucket(0, 0));
  assertEquals(report.byKind.interfaceProperty, bucket(0, 0));
  assertEquals(report.byKind.typeParam, bucket(0, 0));
});

Deno.test("buildReport rounds percentages to two decimals", () => {
  const report = buildReport([
    mkItem("class", "one", "src/rounded.ts", 1, true),
    mkItem("class", "two", "src/rounded.ts", 2, false),
    mkItem("class", "three", "src/rounded.ts", 3, false),
  ], []);

  assertEquals(report.overall, bucket(1, 3));
  assertEquals(report.byKind.class, bucket(1, 3));
});

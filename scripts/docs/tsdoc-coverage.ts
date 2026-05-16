#!/usr/bin/env -S deno run -A

type JsonObject = Record<string, unknown>;

type SymbolKind =
  | "class"
  | "interface"
  | "type"
  | "enum"
  | "function"
  | "variable"
  | "classMethod"
  | "classProperty"
  | "interfaceProperty"
  | "typeParam";

interface SourceLocation {
  filename?: string;
  line?: number;
  col?: number;
}

interface JsDocTag {
  kind?: string;
  name?: string;
  doc?: string;
  value?: string;
}

interface JsDoc {
  doc?: string;
  tags?: JsDocTag[];
}

interface CoverageItem {
  kind: SymbolKind;
  symbol: string;
  file: string;
  line: number;
  documented: boolean;
}

interface CoverageBucket {
  documented: number;
  total: number;
  percent: number;
}

interface CoverageReport {
  overall: CoverageBucket;
  byKind: Record<SymbolKind, CoverageBucket>;
  byFile: Record<string, CoverageBucket>;
  missing: CoverageItem[];
  warnings: string[];
}

const textDecoder = new TextDecoder();
const rootDir = Deno.cwd();

const symbolKinds: SymbolKind[] = [
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

const topLevelKinds: Record<string, SymbolKind> = {
  class: "class",
  interface: "interface",
  typeAlias: "type",
  enum: "enum",
  function: "function",
  variable: "variable",
};

function usage(): never {
  console.error(
    "Usage: deno run -A scripts/docs/tsdoc-coverage.ts [--json] " +
      "[--min-overall PERCENT] <path> [path...]",
  );
  Deno.exit(2);
}

function asObject(value: unknown): JsonObject | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : undefined;
}

function asArray(value: unknown): JsonObject[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const objects: JsonObject[] = [];
  for (const item of value) {
    const object = asObject(item);
    if (object) {
      objects.push(object);
    }
  }
  return objects;
}

function stringField(value: JsonObject | undefined, field: string): string | undefined {
  const fieldValue = value?.[field];
  return typeof fieldValue === "string" ? fieldValue : undefined;
}

function numberField(value: JsonObject | undefined, field: string): number | undefined {
  const fieldValue = value?.[field];
  return typeof fieldValue === "number" ? fieldValue : undefined;
}

function jsDocFrom(value: JsonObject | undefined): JsDoc | undefined {
  return asObject(value?.jsDoc) as JsDoc | undefined;
}

function locationFrom(value: JsonObject | undefined): SourceLocation | undefined {
  return asObject(value?.location) as SourceLocation | undefined;
}

function hasDoc(jsDoc: JsDoc | undefined): boolean {
  if (!jsDoc) {
    return false;
  }

  if (typeof jsDoc.doc === "string" && jsDoc.doc.trim().length > 0) {
    return true;
  }

  return (jsDoc.tags ?? []).some((tag) => {
    const doc = typeof tag.doc === "string" ? tag.doc.trim() : "";
    const value = typeof tag.value === "string" ? tag.value.trim() : "";
    return doc.length > 0 || value.length > 0;
  });
}

function hasNamedTag(jsDoc: JsDoc | undefined, kind: string, name: string): boolean {
  return (jsDoc?.tags ?? []).some((tag) =>
    tag.kind === kind && tag.name === name && typeof tag.doc === "string" &&
    tag.doc.trim().length > 0
  );
}

function hasTypeParamDoc(jsDoc: JsDoc | undefined, name: string): boolean {
  return (jsDoc?.tags ?? []).some((tag) =>
    (tag.kind === "template" || tag.kind === "typeParam" || tag.kind === "typeparam") &&
    tag.name === name &&
    typeof tag.doc === "string" &&
    tag.doc.trim().length > 0
  );
}

function dirname(path: string): string {
  const trimmed = path.length > 1 ? path.replace(/\/+$/, "") : path;
  const index = trimmed.lastIndexOf("/");
  if (index <= 0) {
    return "/";
  }
  return trimmed.slice(0, index);
}

function basename(path: string): string {
  const trimmed = path.length > 1 ? path.replace(/\/+$/, "") : path;
  const index = trimmed.lastIndexOf("/");
  return index === -1 ? trimmed : trimmed.slice(index + 1);
}

function joinPath(base: string, child: string): string {
  return base.endsWith("/") ? `${base}${child}` : `${base}/${child}`;
}

function relativePath(from: string, to: string): string {
  const normalizedFrom = from.replace(/\/+$/, "");
  if (to === normalizedFrom) {
    return ".";
  }
  if (to.startsWith(`${normalizedFrom}/`)) {
    return to.slice(normalizedFrom.length + 1);
  }
  return to;
}

function displayPath(path: string): string {
  return relativePath(rootDir, path).replaceAll("\\", "/");
}

function pathFromLocation(location: SourceLocation | undefined): string {
  const filename = location?.filename;
  if (!filename) {
    return "<unknown>";
  }
  if (filename.startsWith("file://")) {
    return decodeURIComponent(new URL(filename).pathname);
  }
  return filename;
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return false;
    }
    throw error;
  }
}

async function realPath(path: string): Promise<string> {
  try {
    return await Deno.realPath(path);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw error;
    }
    return path.startsWith("/") ? path : joinPath(rootDir, path);
  }
}

async function nearestDenoConfig(path: string): Promise<string | undefined> {
  let current = dirname(await realPath(path));
  while (true) {
    if (
      await exists(joinPath(current, "deno.json")) || await exists(joinPath(current, "deno.jsonc"))
    ) {
      return current;
    }
    const parent = dirname(current);
    if (parent === current) {
      return undefined;
    }
    current = parent;
  }
}

function isSourceFile(path: string): boolean {
  if (path.endsWith(".d.ts") || path.endsWith(".test.ts") || path.endsWith(".test.tsx")) {
    return false;
  }
  if (basename(path) === "fresh.gen.ts") {
    return false;
  }
  return path.endsWith(".ts") || path.endsWith(".tsx");
}

async function collectSourceFiles(path: string, files: string[] = []): Promise<string[]> {
  const resolved = await realPath(path);
  const stat = await Deno.stat(resolved);
  if (stat.isFile) {
    if (isSourceFile(resolved)) {
      files.push(resolved);
    }
    return files;
  }
  if (!stat.isDirectory) {
    return files;
  }

  for await (const entry of Deno.readDir(resolved)) {
    if (entry.name === "node_modules" || entry.name === ".git") {
      continue;
    }

    const child = joinPath(resolved, entry.name);
    if (entry.isDirectory) {
      await collectSourceFiles(child, files);
    } else if (entry.isFile && isSourceFile(child)) {
      files.push(child);
    }
  }
  return files;
}

async function hasExportedSyntax(path: string): Promise<boolean> {
  const source = await Deno.readTextFile(path);
  return /\bexport\b/.test(source);
}

async function loadDocJson(path: string): Promise<{ nodes: JsonObject[]; warning?: string }> {
  const configDir = await nearestDenoConfig(path);
  const cwd = configDir ?? rootDir;
  const sourceArg = relativePath(cwd, path);
  const command = new Deno.Command(Deno.execPath(), {
    args: ["doc", "--json", sourceArg],
    cwd,
    stdout: "piped",
    stderr: "piped",
  });

  const output = await command.output();
  const stdout = textDecoder.decode(output.stdout).trim();
  const stderr = textDecoder.decode(output.stderr).trim();

  if (stdout.length > 0) {
    try {
      const parsed = JSON.parse(stdout) as { nodes?: unknown };
      return { nodes: asArray(parsed.nodes) };
    } catch (error) {
      return {
        nodes: [],
        warning: `${displayPath(path)}: failed to parse deno doc JSON: ${error}`,
      };
    }
  }

  if (!output.success) {
    const detail = stderr.split("\n").find((line) => line.trim().length > 0) ??
      `deno doc exited with ${output.code}`;
    return { nodes: [], warning: `${displayPath(path)}: ${detail}` };
  }

  return { nodes: [] };
}

function isPublic(member: JsonObject): boolean {
  const accessibility = member.accessibility;
  return accessibility !== "private" && accessibility !== "protected";
}

function typeParamsFrom(definition: JsonObject | undefined): JsonObject[] {
  return asArray(definition?.typeParams);
}

function addItem(items: Map<string, CoverageItem>, item: CoverageItem): void {
  const key = `${item.kind}\0${item.file}\0${item.line}\0${item.symbol}`;
  const existing = items.get(key);
  if (!existing || (!existing.documented && item.documented)) {
    items.set(key, item);
  }
}

function addTypeParams(
  items: Map<string, CoverageItem>,
  parentSymbol: string,
  jsDoc: JsDoc | undefined,
  typeParams: JsonObject[],
  location: SourceLocation | undefined,
): void {
  for (const typeParam of typeParams) {
    const name = stringField(typeParam, "name");
    if (!name) {
      continue;
    }
    const file = displayPath(pathFromLocation(location));
    addItem(items, {
      kind: "typeParam",
      symbol: `${parentSymbol}<${name}>`,
      file,
      line: location?.line ?? 0,
      documented: hasTypeParamDoc(jsDoc, name) || hasDoc(jsDocFrom(typeParam)),
    });
  }
}

function addTopLevelNode(items: Map<string, CoverageItem>, node: JsonObject): void {
  const kind = stringField(node, "kind");
  const symbolKind = kind ? topLevelKinds[kind] : undefined;
  if (!symbolKind || stringField(node, "declarationKind") !== "export") {
    return;
  }

  const name = stringField(node, "name");
  const location = locationFrom(node);
  if (!name || !location) {
    return;
  }

  const file = displayPath(pathFromLocation(location));
  addItem(items, {
    kind: symbolKind,
    symbol: name,
    file,
    line: location.line ?? 0,
    documented: hasDoc(jsDocFrom(node)),
  });

  const jsDoc = jsDocFrom(node);
  if (kind === "class") {
    addTypeParams(items, name, jsDoc, typeParamsFrom(asObject(node.classDef)), location);
    addClassMembers(items, node, name);
  } else if (kind === "interface") {
    addTypeParams(items, name, jsDoc, typeParamsFrom(asObject(node.interfaceDef)), location);
    addInterfaceMembers(items, node, name);
  } else if (kind === "function") {
    addTypeParams(items, name, jsDoc, typeParamsFrom(asObject(node.functionDef)), location);
  } else if (kind === "typeAlias") {
    addTypeParams(items, name, jsDoc, typeParamsFrom(asObject(node.typeAliasDef)), location);
  }
}

function addClassMembers(
  items: Map<string, CoverageItem>,
  node: JsonObject,
  className: string,
): void {
  const classDef = asObject(node.classDef);

  for (const property of asArray(classDef?.properties)) {
    if (!isPublic(property)) {
      continue;
    }
    const name = stringField(property, "name");
    const location = locationFrom(property);
    if (!name || !location) {
      continue;
    }
    addItem(items, {
      kind: "classProperty",
      symbol: `${className}.${name}`,
      file: displayPath(pathFromLocation(location)),
      line: location.line ?? 0,
      documented: hasDoc(jsDocFrom(property)),
    });
  }

  for (const constructor of asArray(classDef?.constructors)) {
    const constructorLocation = locationFrom(constructor) ?? locationFrom(node);
    const constructorDoc = jsDocFrom(constructor);
    for (const param of asArray(constructor.params)) {
      if (param.accessibility !== "public") {
        continue;
      }
      const name = stringField(param, "name");
      if (!name) {
        continue;
      }
      addItem(items, {
        kind: "classProperty",
        symbol: `${className}.${name}`,
        file: displayPath(pathFromLocation(constructorLocation)),
        line: constructorLocation?.line ?? 0,
        documented: hasNamedTag(constructorDoc, "param", name),
      });
    }
  }

  for (const method of asArray(classDef?.methods)) {
    if (!isPublic(method)) {
      continue;
    }
    const name = stringField(method, "name");
    const location = locationFrom(method);
    if (!name || !location) {
      continue;
    }
    const symbol = `${className}.${name}`;
    const jsDoc = jsDocFrom(method);
    addItem(items, {
      kind: "classMethod",
      symbol,
      file: displayPath(pathFromLocation(location)),
      line: location.line ?? 0,
      documented: hasDoc(jsDoc),
    });
    addTypeParams(items, symbol, jsDoc, typeParamsFrom(asObject(method.functionDef)), location);
  }
}

function addInterfaceMembers(
  items: Map<string, CoverageItem>,
  node: JsonObject,
  interfaceName: string,
): void {
  const interfaceDef = asObject(node.interfaceDef);
  for (const property of asArray(interfaceDef?.properties)) {
    const name = stringField(property, "name");
    const location = locationFrom(property);
    if (!name || !location) {
      continue;
    }
    addItem(items, {
      kind: "interfaceProperty",
      symbol: `${interfaceName}.${name}`,
      file: displayPath(pathFromLocation(location)),
      line: location.line ?? 0,
      documented: hasDoc(jsDocFrom(property)),
    });
  }
}

function bucketFor(items: CoverageItem[]): CoverageBucket {
  const total = items.length;
  const documented = items.filter((item) => item.documented).length;
  return {
    documented,
    total,
    percent: total === 0 ? 100 : Number(((documented / total) * 100).toFixed(2)),
  };
}

function buildReport(items: CoverageItem[], warnings: string[]): CoverageReport {
  const byKind = Object.fromEntries(
    symbolKinds.map((kind) => [kind, bucketFor(items.filter((item) => item.kind === kind))]),
  ) as Record<SymbolKind, CoverageBucket>;

  const files = [...new Set(items.map((item) => item.file))].sort();
  const byFile = Object.fromEntries(
    files.map((file) => [file, bucketFor(items.filter((item) => item.file === file))]),
  );

  return {
    overall: bucketFor(items),
    byKind,
    byFile,
    missing: items.filter((item) => !item.documented)
      .sort((a, b) =>
        a.file.localeCompare(b.file) || a.line - b.line ||
        a.symbol.localeCompare(b.symbol)
      ),
    warnings,
  };
}

function printReport(report: CoverageReport): void {
  console.log("TypeScript documentation coverage");
  console.log(
    `Overall: ${report.overall.percent}% ` +
      `(${report.overall.documented}/${report.overall.total})`,
  );

  console.log("\nBy kind:");
  for (const kind of symbolKinds) {
    const bucket = report.byKind[kind];
    console.log(`  ${kind}: ${bucket.percent}% (${bucket.documented}/${bucket.total})`);
  }

  if (report.missing.length > 0) {
    console.log("\nMissing documentation:");
    let currentFile = "";
    for (const item of report.missing) {
      if (item.file !== currentFile) {
        currentFile = item.file;
        console.log(`${currentFile}:`);
      }
      console.log(`  L${item.line} ${item.kind} ${item.symbol}`);
    }
  }

  if (report.warnings.length > 0) {
    console.log("\nWarnings:");
    for (const warning of report.warnings) {
      console.log(`  ${warning}`);
    }
  }
}

async function main(): Promise<void> {
  const paths: string[] = [];
  let json = false;
  let minOverall: number | undefined;

  for (let index = 0; index < Deno.args.length; index += 1) {
    const arg = Deno.args[index];
    if (arg === "--json") {
      json = true;
    } else if (arg === "--min-overall") {
      const value = Deno.args[++index];
      if (!value) {
        usage();
      }
      minOverall = Number(value);
      if (!Number.isFinite(minOverall)) {
        usage();
      }
    } else if (arg.startsWith("--min-overall=")) {
      minOverall = Number(arg.slice("--min-overall=".length));
      if (!Number.isFinite(minOverall)) {
        usage();
      }
    } else if (arg.startsWith("--")) {
      usage();
    } else {
      paths.push(arg);
    }
  }

  if (paths.length === 0) {
    usage();
  }

  const items = new Map<string, CoverageItem>();
  const warnings: string[] = [];
  const sourceFiles = [
    ...new Set((await Promise.all(paths.map((path) => collectSourceFiles(path))))
      .flat()),
  ].sort();

  for (const sourceFile of sourceFiles) {
    if (!(await hasExportedSyntax(sourceFile))) {
      continue;
    }

    const { nodes, warning } = await loadDocJson(sourceFile);
    if (warning) {
      warnings.push(warning);
    }
    for (const node of nodes) {
      addTopLevelNode(items, node);
    }
  }

  const report = buildReport([...items.values()], warnings);
  if (json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printReport(report);
  }

  if (minOverall !== undefined && report.overall.percent < minOverall) {
    console.error(
      `TypeScript documentation coverage ${report.overall.percent}% is below ` +
        `the required ${minOverall}%`,
    );
    Deno.exit(1);
  }
}

await main();

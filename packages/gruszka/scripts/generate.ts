import { expandGlob } from "@std/fs/expand-glob";
import { dirname, fromFileUrl, join, relative } from "@std/path";

const SCRIPT_DIR = dirname(fromFileUrl(import.meta.url));
const PACKAGE_DIR = dirname(SCRIPT_DIR);
const REPO_ROOT = dirname(dirname(PACKAGE_DIR));
const DEFAULT_LEXICONS_DIR = join(
  REPO_ROOT,
  "Garazyk",
  "Resources",
  "lexicons",
);
const DEFAULT_OUT_FILE = join(PACKAGE_DIR, "lexicons.ts");

export type LexiconDefinitionKind =
  | "record"
  | "query"
  | "procedure"
  | "subscription"
  | "other";

interface LexiconDoc {
  lexicon: number;
  id: string;
  defs: Record<string, LexiconDef>;
}

interface LexiconDef extends LexiconSchema {
  type?: string;
  parameters?: LexiconParams;
  input?: LexiconBody;
  output?: LexiconBody;
  record?: LexiconSchema;
}

interface LexiconParams {
  properties?: Record<string, LexiconSchema>;
  required?: string[];
}

interface LexiconBody {
  encoding?: string;
  schema?: LexiconSchema;
}

interface LexiconSchema {
  type?: string;
  ref?: string;
  refs?: string[];
  closed?: boolean;
  properties?: Record<string, LexiconSchema>;
  required?: string[];
  items?: LexiconSchema;
}

interface LocatedLexiconDoc {
  doc: LexiconDoc;
  path: string;
}

export interface GenerateLexiconsOptions {
  lexiconsDir?: string;
  outFile?: string;
}

export interface GenerateLexiconsResult {
  lexiconCount: number;
  endpointCount: number;
  outFile: string;
}

export async function generateLexicons(
  options: GenerateLexiconsOptions = {},
): Promise<GenerateLexiconsResult> {
  const lexiconsDir = options.lexiconsDir ?? DEFAULT_LEXICONS_DIR;
  const outFile = options.outFile ?? DEFAULT_OUT_FILE;
  const docs: LocatedLexiconDoc[] = [];
  for await (const file of expandGlob(join(lexiconsDir, "**/*.json"))) {
    if (file.isFile) {
      const text = await Deno.readTextFile(file.path);
      try {
        docs.push({ doc: JSON.parse(text) as LexiconDoc, path: file.path });
      } catch (e) {
        console.error(`Error parsing ${file.path}:`, e);
      }
    }
  }

  const selectedDocs = selectCanonicalDocs(docs, lexiconsDir);
  const classifiedDocs = classifyLexicons(selectedDocs);
  assertNonEmptyInventory(classifiedDocs, lexiconsDir, outFile);

  const generated = renderLexicons(classifiedDocs);

  await Deno.mkdir(dirname(outFile), { recursive: true });
  await Deno.writeTextFile(outFile, generated.source);
  return {
    lexiconCount: generated.lexiconCount,
    endpointCount: generated.endpointCount,
    outFile,
  };
}

async function main() {
  const result = await generateLexicons();
  console.log(
    `Wrote ${result.lexiconCount} lexicons (${result.endpointCount} endpoints) to ${result.outFile}`,
  );
}

function selectCanonicalDocs(
  docs: LocatedLexiconDoc[],
  lexiconsDir: string,
): LexiconDoc[] {
  const byId = new Map<string, LocatedLexiconDoc[]>();
  for (const doc of docs) {
    const current = byId.get(doc.doc.id) ?? [];
    current.push(doc);
    byId.set(doc.doc.id, current);
  }

  const selected: LocatedLexiconDoc[] = [];
  const duplicateErrors: string[] = [];

  for (const [id, candidates] of byId) {
    if (candidates.length === 1) {
      selected.push(candidates[0]);
      continue;
    }

    const canonicalPath = join(lexiconsDir, ...id.split(".")) + ".json";
    const canonicalCandidates = candidates.filter((candidate) =>
      candidate.path === canonicalPath
    );
    if (canonicalCandidates.length === 1) {
      selected.push(canonicalCandidates[0]);
      continue;
    }

    const paths = candidates
      .map((candidate) => relative(lexiconsDir, candidate.path))
      .sort();
    duplicateErrors.push(
      `${id}: ${paths.join(", ")} (expected canonical path ${
        relative(lexiconsDir, canonicalPath)
      })`,
    );
  }

  if (duplicateErrors.length > 0) {
    throw new Error(
      `Duplicate lexicon ids without a unique canonical path:\n${
        duplicateErrors.sort().join("\n")
      }`,
    );
  }

  return selected.map(({ doc }) => doc).sort(compareLexiconDocs);
}

interface ClassifiedLexicons {
  all: LexiconDoc[];
  records: LexiconDoc[];
  queries: LexiconDoc[];
  procedures: LexiconDoc[];
  subscriptions: LexiconDoc[];
  other: LexiconDoc[];
}

function classifyLexicons(docs: LexiconDoc[]): ClassifiedLexicons {
  const classified: ClassifiedLexicons = {
    all: [...docs].sort(compareLexiconDocs),
    records: [],
    queries: [],
    procedures: [],
    subscriptions: [],
    other: [],
  };

  for (const doc of classified.all) {
    switch (definitionKind(doc)) {
      case "record":
        classified.records.push(doc);
        break;
      case "query":
        classified.queries.push(doc);
        break;
      case "procedure":
        classified.procedures.push(doc);
        break;
      case "subscription":
        classified.subscriptions.push(doc);
        break;
      case "other":
        classified.other.push(doc);
        break;
    }
  }

  return classified;
}

function definitionKind(doc: LexiconDoc): LexiconDefinitionKind {
  switch (doc.defs?.main?.type) {
    case "record":
    case "query":
    case "procedure":
    case "subscription":
      return doc.defs.main.type;
    default:
      return "other";
  }
}

function assertNonEmptyInventory(
  classified: ClassifiedLexicons,
  lexiconsDir: string,
  outFile: string,
): void {
  if (classified.all.length === 0) {
    throw new Error(
      `No lexicon documents found in ${lexiconsDir}; refusing to overwrite ${outFile}`,
    );
  }

  const endpointCount = classified.queries.length +
    classified.procedures.length + classified.subscriptions.length;
  if (endpointCount === 0) {
    throw new Error(
      `No endpoint definitions found in ${lexiconsDir}; refusing to overwrite ${outFile}`,
    );
  }
}

function renderLexicons(classified: ClassifiedLexicons): {
  source: string;
  lexiconCount: number;
  endpointCount: number;
} {
  const resolver = createResolver(classified.all);

  let out = `// GENERATED CODE - DO NOT EDIT
// This file was generated by scripts/generate.ts
/* eslint-disable */
// @ts-nocheck

export interface LexiconQuery<Params = unknown, Input = unknown, Output = unknown> {
  inputEncoding?: string;
  outputEncoding?: string;
  params?: Params;
  input?: Input;
  output?: Output;
}

export interface LexiconProcedure<Input = unknown, Output = unknown> {
  inputEncoding?: string;
  outputEncoding?: string;
  input?: Input;
  output?: Output;
}

export type BinaryXrpcResponse = [status: number, contentType: string, data: Uint8Array];

export interface LexiconDefs {
`;

  for (const doc of classified.all) {
    out += `  ${tsString(doc.id)}: {\n`;
    for (const [defName, def] of sortedEntries(doc.defs)) {
      out += `    ${tsString(defName)}: ${
        mapDef(doc.id, defName, def, resolver)
      };\n`;
    }
    out += "  };\n";
  }

  out += `}

export interface Lexicons {
`;

  const validDocs = [
    ...classified.queries,
    ...classified.procedures,
    ...classified.records,
  ].sort(compareLexiconDocs);

  for (const doc of validDocs) {
    const mainDef = doc.defs["main"];

    if (mainDef.type === "query" || mainDef.type === "procedure") {
      out += `  "${doc.id}": {\n`;
      if (mainDef.type === "query") {
        out += `    type: "query";\n`;
        out += `    outputEncoding: ${tsString(outputEncoding(mainDef))};\n`;
        // parameters
        if (mainDef.parameters && mainDef.parameters.properties) {
          out += `    params: {\n`;
          for (
            const [key, prop] of sortedEntries(mainDef.parameters.properties)
          ) {
            const required = mainDef.parameters.required?.includes(key)
              ? ""
              : "?";
            out += `      ${tsString(key)}${required}: ${
              mapType(doc.id, prop, resolver)
            };\n`;
          }
          out += `    };\n`;
        } else {
          out += `    params: Record<string, never>;\n`;
        }
      } else {
        out += `    type: "procedure";\n`;
        out += `    inputEncoding: ${tsString(inputEncoding(mainDef))};\n`;
        out += `    outputEncoding: ${tsString(outputEncoding(mainDef))};\n`;
      }

      // input
      if (mainDef.input && mainDef.input.schema) {
        out += `    input: ${
          mapSchema(doc.id, mainDef.input.schema, resolver)
        };\n`;
      } else if (isBinaryEncoding(mainDef.input?.encoding)) {
        out += `    input: Uint8Array;\n`;
      } else {
        out += `    input: never;\n`;
      }

      // output
      if (mainDef.output && mainDef.output.schema) {
        out += `    output: ${
          mapSchema(doc.id, mainDef.output.schema, resolver)
        };\n`;
      } else if (isBinaryEncoding(mainDef.output?.encoding)) {
        out += `    output: BinaryXrpcResponse;\n`;
      } else {
        out += `    output: never;\n`;
      }

      out += `  };\n`;
    } else if (mainDef.type === "record") {
      out += `  "${doc.id}": {\n`;
      out += `    type: "record";\n`;
      out += `    record: LexiconDefs[${tsString(doc.id)}]["main"];\n`;
      out += `  };\n`;
    }
  }

  out += "}\n\n";

  out += "export const LEXICON_DEFINITION_KINDS = {\n";
  for (const doc of classified.all) {
    out += `  ${tsString(doc.id)}: ${tsString(definitionKind(doc))},\n`;
  }
  out += "} as const;\n\n";

  out += "export const LEXICON_METHOD_TYPES = {\n";
  for (
    const doc of [...classified.queries, ...classified.procedures].sort(
      compareLexiconDocs,
    )
  ) {
    out += `  ${tsString(doc.id)}: ${tsString(definitionKind(doc))},\n`;
  }
  out += "} as const;\n\n";

  out += "export const LEXICON_METHOD_INPUT_ENCODINGS = {\n";
  for (const doc of classified.procedures) {
    out += `  ${tsString(doc.id)}: ${
      tsString(inputEncoding(doc.defs.main))
    },\n`;
  }
  out += "} as const;\n\n";

  out += "export const LEXICON_METHOD_OUTPUT_ENCODINGS = {\n";
  for (
    const doc of [...classified.queries, ...classified.procedures].sort(
      compareLexiconDocs,
    )
  ) {
    out += `  ${tsString(doc.id)}: ${
      tsString(outputEncoding(doc.defs.main))
    },\n`;
  }
  out += "} as const;\n\n";

  // The catalog is exact, but the public client keeps its existing dynamic
  // dispatch contract. Narrowing it would be a separate client migration.
  out += `
export type LexiconIds = string;
export type LexiconQueryIds = string;
export type LexiconProcedureIds = string;

export type QueryParams<K extends string> =
  K extends keyof Lexicons
    ? Lexicons[K] extends { params: infer Params } ? Params : unknown
    : unknown;
export type QueryOutput<K extends string> =
  K extends keyof Lexicons
    ? Lexicons[K] extends { output: infer Output } ? Output : unknown
    : unknown;
export type ProcedureInput<K extends string> =
  K extends keyof Lexicons
    ? Lexicons[K] extends { input: infer Input } ? Input : unknown
    : unknown;
export type ProcedureOutput<K extends string> =
  K extends keyof Lexicons
    ? Lexicons[K] extends { output: infer Output } ? Output : unknown
    : unknown;
export type QueryOutputEncoding<K extends string> =
  K extends keyof Lexicons
    ? Lexicons[K] extends { outputEncoding: infer Encoding } ? Encoding : unknown
    : unknown;
export type ProcedureInputEncoding<K extends string> =
  K extends keyof Lexicons
    ? Lexicons[K] extends { inputEncoding: infer Encoding } ? Encoding : unknown
    : unknown;
export type ProcedureOutputEncoding<K extends string> =
  K extends keyof Lexicons
    ? Lexicons[K] extends { outputEncoding: infer Encoding } ? Encoding : unknown
    : unknown;

export interface CallOptions {
  headers?: { Authorization?: string };
}

export interface XrpcCaller {
  call(method: string, data?: unknown, tokenOrOpts?: string | CallOptions): Promise<unknown>;
}

/** Typed nested API client backed by a Proxy. */
export interface GeneratedClient {
`;

  interface ClientTree {
    [key: string]: LexiconDoc | ClientTree;
  }
  const tree: ClientTree = {};
  for (
    const doc of [...classified.queries, ...classified.procedures].sort(
      compareLexiconDocs,
    )
  ) {
    const parts = doc.id.split(".");
    let current = tree;
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      if (index === parts.length - 1) {
        current[part] = doc;
      } else {
        current[part] = current[part] || {};
        current = current[part] as ClientTree;
      }
    }
  }

  function isLexiconDoc(value: LexiconDoc | ClientTree): value is LexiconDoc {
    return "id" in value && typeof value.id === "string";
  }

  function generateInterface(node: ClientTree, indent: string): string {
    let result = "";
    for (
      const [key, value] of Object.entries(node).sort(([a], [b]) =>
        a.localeCompare(b)
      )
    ) {
      if (isLexiconDoc(value)) {
        const doc = value;
        if (definitionKind(doc) === "query") {
          result +=
            `${indent}"${key}"(params?: QueryParams<"${doc.id}">, tokenOrOpts?: string | CallOptions): Promise<QueryOutput<"${doc.id}">>;\n`;
        } else {
          result +=
            `${indent}"${key}"(input?: ProcedureInput<"${doc.id}">, tokenOrOpts?: string | CallOptions): Promise<ProcedureOutput<"${doc.id}">>;\n`;
        }
      } else {
        result += `${indent}"${key}": {\n`;
        result += generateInterface(value, indent + "  ");
        result += `${indent}};\n`;
      }
    }
    return result;
  }

  out += generateInterface(tree, "  ");
  out += `  [method: string]: any;
}

export function createGeneratedClient(caller: XrpcCaller): GeneratedClient {
  function buildProxy(path: string[]): any {
    const nsid = path.join(".");
    const target = function (...args: unknown[]): Promise<unknown> {
      if (!nsid) {
        throw new TypeError("GeneratedClient root cannot be called directly; use a namespace chain");
      }
      return caller.call(nsid, args[0], args[1] as string | CallOptions | undefined);
    };

    return new Proxy(target, {
      get(_target, property: string | symbol) {
        if (typeof property === "symbol" || property === "then") return undefined;
        if (property === "toJSON") return () => nsid;
        if (property === "toString") return () => "[GeneratedClient " + (nsid || "root") + "]";
        return buildProxy([...path, property]);
      },
      has(_target, property: string | symbol) {
        return typeof property !== "symbol";
      },
    });
  }

  return buildProxy([]) as unknown as GeneratedClient;
}
`;

  return {
    source: out,
    lexiconCount: classified.all.length,
    endpointCount: classified.queries.length + classified.procedures.length +
      classified.subscriptions.length,
  };
}

function compareLexiconDocs(a: LexiconDoc, b: LexiconDoc): number {
  return a.id.localeCompare(b.id);
}

function sortedEntries<T>(record: Record<string, T>): Array<[string, T]> {
  return Object.keys(record).sort().map((key) => [key, record[key]]);
}

interface LexiconResolver {
  hasRef(ref: string, currentDocId: string): boolean;
  typeForRef(ref: string, currentDocId: string): string;
}

function createResolver(docs: LexiconDoc[]): LexiconResolver {
  const defNamesByDoc = new Map<string, Set<string>>();
  for (const doc of docs) {
    defNamesByDoc.set(doc.id, new Set(Object.keys(doc.defs)));
  }

  return {
    hasRef(ref: string, currentDocId: string): boolean {
      const target = parseRef(ref, currentDocId);
      return defNamesByDoc.get(target.docId)?.has(target.defName) ?? false;
    },
    typeForRef(ref: string, currentDocId: string): string {
      const target = parseRef(ref, currentDocId);
      if (!defNamesByDoc.get(target.docId)?.has(target.defName)) {
        return `any /* unresolved ref: ${ref} */`;
      }
      return `LexiconDefs[${tsString(target.docId)}][${
        tsString(target.defName)
      }]`;
    },
  };
}

function parseRef(
  ref: string,
  currentDocId: string,
): { docId: string; defName: string } {
  if (ref.startsWith("#")) {
    return { docId: currentDocId, defName: ref.slice(1) || "main" };
  }

  const hashIndex = ref.indexOf("#");
  if (hashIndex === -1) {
    return { docId: ref, defName: "main" };
  }

  return {
    docId: ref.slice(0, hashIndex),
    defName: ref.slice(hashIndex + 1) || "main",
  };
}

function mapDef(
  docId: string,
  defName: string,
  def: LexiconDef,
  resolver: LexiconResolver,
): string {
  if (defName === "main" && def.type === "record") {
    return mapSchema(docId, def.record, resolver);
  }

  if (def.type === "query" || def.type === "procedure") {
    return "never";
  }

  return mapType(docId, def, resolver);
}

function mapType(
  docId: string,
  prop: LexiconSchema,
  resolver: LexiconResolver,
): string {
  if (prop.type === "string") return "string";
  if (prop.type === "integer" || prop.type === "number") return "number";
  if (prop.type === "boolean") return "boolean";
  if (prop.type === "array") {
    return `Array<${
      mapType(docId, prop.items || { type: "unknown" }, resolver)
    }>`;
  }
  if (prop.type === "object") return mapSchema(docId, prop, resolver);
  if (prop.type === "blob") return "any /* blob */";
  if (prop.type === "bytes") return stringBytesType();
  if (prop.type === "cid-link") return "unknown /* cid-link */";
  if (prop.type === "unknown") return "unknown";
  if (prop.type === "token") return "string";
  if (prop.type === "ref" && prop.ref) {
    return resolver.typeForRef(prop.ref, docId);
  }
  if (prop.type === "union") return mapUnion(docId, prop, resolver);
  return "any";
}

function mapUnion(
  docId: string,
  prop: LexiconSchema,
  resolver: LexiconResolver,
): string {
  const resolvedRefs = (prop.refs ?? []).map((ref) =>
    resolver.typeForRef(ref, docId)
  );
  const knownRefs = resolvedRefs.length > 0 ? resolvedRefs : ["never"];
  if (prop.closed) return knownRefs.join(" | ");
  return `${knownRefs.join(" | ")} | Record<string, any>`;
}

function mapSchema(
  docId: string,
  schema: LexiconSchema | undefined,
  resolver: LexiconResolver,
): string {
  if (!schema) return "any";
  if (schema.type === "object" && schema.properties) {
    let out = "{\n";
    for (const [key, prop] of sortedEntries(schema.properties)) {
      const required = schema.required?.includes(key) ? "" : "?";
      out += `      ${tsString(key)}${required}: ${
        mapType(docId, prop, resolver)
      };\n`;
    }
    out += "    }";
    return out;
  }
  if (schema.type === "object") return "Record<string, never>";
  return mapType(docId, schema, resolver);
}

function stringBytesType(): string {
  return "{ $bytes: string } | string";
}

function inputEncoding(def: LexiconDef): string {
  return def.input?.encoding ?? "application/json";
}

function outputEncoding(def: LexiconDef): string {
  return def.output?.encoding ?? "application/json";
}

function isBinaryEncoding(encoding: string | undefined): boolean {
  return encoding !== undefined && encoding !== "application/json";
}

function tsString(value: string): string {
  return JSON.stringify(value);
}

if (import.meta.main) {
  main();
}

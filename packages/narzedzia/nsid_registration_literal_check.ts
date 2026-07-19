#!/usr/bin/env -S deno run --allow-read

import { join, relative } from "@std/path";

const SOURCE_ROOT = ["Garazyk", "Sources"] as const;
const INTERNAL_METHOD_ID = /^_[A-Za-z0-9_-]+$/;
const REGISTRATION_LITERAL_PATTERN =
  /\bregisterMethod\s*:\s*@"((?:\\.|[^"\\])*)"/g;

export interface RawNsidRegistrationLiteral {
  readonly file: string;
  readonly line: number;
  readonly literal: string;
}

/**
 * Removes Objective-C comments while preserving every newline and non-comment
 * character position, so diagnostics can use offsets from the original source.
 */
export function stripObjectiveCComments(source: string): string {
  let result = "";
  let state: "code" | "lineComment" | "blockComment" | "string" | "character" =
    "code";

  for (let index = 0; index < source.length; index++) {
    const character = source[index];
    const nextCharacter = source[index + 1];

    if (state === "lineComment") {
      if (character === "\n") {
        result += character;
        state = "code";
      } else {
        result += " ";
      }
      continue;
    }

    if (state === "blockComment") {
      if (character === "*" && nextCharacter === "/") {
        result += "  ";
        index++;
        state = "code";
      } else {
        result += character === "\n" ? "\n" : " ";
      }
      continue;
    }

    if (state === "string" || state === "character") {
      result += character;
      if (character === "\\" && nextCharacter !== undefined) {
        result += nextCharacter;
        index++;
      } else if (
        (state === "string" && character === '"') ||
        (state === "character" && character === "'")
      ) {
        state = "code";
      }
      continue;
    }

    if (character === "/" && nextCharacter === "/") {
      result += "  ";
      index++;
      state = "lineComment";
    } else if (character === "/" && nextCharacter === "*") {
      result += "  ";
      index++;
      state = "blockComment";
    } else {
      result += character;
      if (character === '"') {
        state = "string";
      } else if (character === "'") {
        state = "character";
      }
    }
  }

  return result;
}

/** Finds direct NSString literals passed as the first registerMethod: argument. */
export function findRawNsidRegistrationLiterals(
  source: string,
  file: string,
): RawNsidRegistrationLiteral[] {
  const commentFreeSource = stripObjectiveCComments(source);
  const literals: RawNsidRegistrationLiteral[] = [];
  REGISTRATION_LITERAL_PATTERN.lastIndex = 0;

  for (
    let match = REGISTRATION_LITERAL_PATTERN.exec(commentFreeSource);
    match;
    match = REGISTRATION_LITERAL_PATTERN.exec(commentFreeSource)
  ) {
    const literal = match[1];
    if (literal === undefined || INTERNAL_METHOD_ID.test(literal)) continue;

    const literalOffset = match.index + match[0].indexOf('@"');
    const prefix = source.slice(0, literalOffset);
    const line = prefix.split("\n").length;
    literals.push({ file, line, literal });
  }

  return literals;
}

async function collectObjectiveCSourceFiles(
  directory: string,
): Promise<string[]> {
  const files: string[] = [];

  for await (const entry of Deno.readDir(directory)) {
    const path = join(directory, entry.name);
    if (entry.isDirectory) {
      files.push(...await collectObjectiveCSourceFiles(path));
    } else if (
      entry.isFile && (entry.name.endsWith(".h") || entry.name.endsWith(".m") ||
        entry.name.endsWith(".mm"))
    ) {
      files.push(path);
    }
  }

  return files;
}

/** Scans production Objective-C sources only, never test fixtures or generated plans. */
export async function findRawNsidRegistrationLiteralsInTree(
  root: string,
): Promise<RawNsidRegistrationLiteral[]> {
  const sourceDirectory = join(root, ...SOURCE_ROOT);
  const files = await collectObjectiveCSourceFiles(sourceDirectory);
  files.sort();

  const literals: RawNsidRegistrationLiteral[] = [];
  for (const file of files) {
    const source = await Deno.readTextFile(file);
    literals.push(
      ...findRawNsidRegistrationLiterals(source, relative(root, file)),
    );
  }

  return literals;
}

export async function main(args = Deno.args): Promise<void> {
  const root = args[0] ?? Deno.cwd();
  const literals = await findRawNsidRegistrationLiteralsInTree(root);

  if (literals.length === 0) {
    console.log("No raw XRPC registration literals found.");
    return;
  }

  console.error(
    "Raw XRPC registration literals are forbidden; use kGZXrpcNSID_* constants:",
  );
  for (const { file, line, literal } of literals) {
    console.error(`${file}:${line}: @\"${literal}\"`);
  }
  Deno.exitCode = 1;
}

if (import.meta.main) {
  await main();
}

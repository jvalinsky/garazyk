#!/usr/bin/env -S deno run -A
import { basename, dirname, join, relative, resolve } from "@std/path";

interface MethodInfo {
  kind: "+" | "-";
  returnType: string;
  fullText: string;
  name: string;
}

interface Args {
  header: string;
  output: string;
  targetClass?: string;
}

function parseArgs(argv: string[]): Args {
  let header = "";
  let output = "Garazyk/Tests/CharacterizationTests";
  let targetClass: string | undefined;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--output") output = argv[++i] ?? output;
    else if (arg === "--target-class") targetClass = argv[++i];
    else if (!header) header = arg;
    else {
      console.error(`Unexpected argument: ${arg}`);
      Deno.exit(2);
    }
  }
  if (!header) {
    console.error(
      "Usage: scripts/dev/generate_characterization_tests.ts HEADER [--output DIR] [--target-class CLASS]",
    );
    Deno.exit(2);
  }
  return { header, output, targetClass };
}

async function parseHeader(headerPath: string): Promise<Record<string, MethodInfo[]>> {
  const content = await Deno.readTextFile(headerPath);
  const chunks = content.split(/(@interface\s+\w+)/);
  const classes: Record<string, MethodInfo[]> = {};
  let currentClass: string | undefined;

  for (const chunk of chunks) {
    const classMatch = chunk.match(/^@interface\s+(\w+)/);
    if (classMatch) {
      currentClass = classMatch[1];
      continue;
    }
    if (!currentClass) continue;

    const methods: MethodInfo[] = [];
    const methodPattern = /^\s*([+-])\s*\(([^)]+)\)([^;]+);/gm;
    for (const match of chunk.matchAll(methodPattern)) {
      const signature = match[3].trim();
      methods.push({
        kind: match[1] as "+" | "-",
        returnType: match[2].trim(),
        fullText: match[0].trim(),
        name: signature.split(":")[0].trim(),
      });
    }
    classes[currentClass] = methods;
    currentClass = undefined;
  }

  return classes;
}

function importPathForHeader(headerPath: string): string {
  const normalized = resolve(headerPath);
  const marker = "Garazyk/Sources/";
  const idx = normalized.indexOf(marker);
  return idx >= 0 ? normalized.slice(idx + marker.length) : basename(headerPath);
}

function generateTestContent(className: string, methods: MethodInfo[], headerPath: string): string {
  const importPath = importPathForHeader(headerPath);
  let content = `#import "CharacterizationTestBase.h"
#import "${importPath}"

@interface ${className}CharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) ${className} *subject;

@end

@implementation ${className}CharacterizationTests

- (void)setUp {
    [super setUp];
    // TODO: Initialize self.subject
    // self.subject = [[${className} alloc] init];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for ${className}
 * Generated automatically. Please implement specific scenarios.
 */
`;

  const seen = new Set<string>();
  for (const method of methods) {
    const kindPrefix = method.kind === "+" ? "Class_" : "";
    const baseName = `testCharacterization_${kindPrefix}${method.name}`;
    let testName = baseName;
    let counter = 1;
    while (seen.has(testName)) testName = `${baseName}_${++counter}`;
    seen.add(testName);
    const actLine = method.kind === "+"
      ? `// [${className} ${method.name}...];`
      : `// [self.subject ${method.name}...];`;

    content += `
- (void)${testName} {
    /* Target Method:
     ${method.fullText}
    */

    // 1. Arrange

    // 2. Act
    ${actLine}

    // 3. Assert
    // XCTFail(@"Test not implemented");
}
`;
  }

  return `${content}\n@end\n`;
}

async function main() {
  const args = parseArgs(Deno.args);
  try {
    await Deno.stat(args.header);
  } catch {
    console.error(`Error: Header file not found: ${args.header}`);
    Deno.exit(1);
  }

  const classes = await parseHeader(args.header);
  const names = Object.keys(classes);
  if (names.length === 0) {
    console.error("Error: Could not find any @interface definitions in header.");
    Deno.exit(1);
  }

  let target = args.targetClass;
  if (!target) {
    const root = basename(args.header).replace(/\.[^.]+$/, "");
    target = classes[root] ? root : names[0];
    if (target !== root) {
      console.log(`Warning: Class '${root}' not found in header. Defaulting to '${target}'.`);
    }
  }
  if (!classes[target]) {
    console.error(`Error: Target class '${target}' not found in ${names.join(", ")}`);
    Deno.exit(1);
  }

  console.log(`Generating tests for class: ${target} with ${classes[target].length} methods.`);
  const outputPath = join(args.output, `${target}CharacterizationTests.m`);
  await Deno.mkdir(dirname(outputPath), { recursive: true });
  try {
    await Deno.stat(outputPath);
    console.log(`Warning: ${outputPath} already exists. Skipping generation to avoid overwrite.`);
    return;
  } catch {
    // Good: the output does not exist.
  }
  await Deno.writeTextFile(outputPath, generateTestContent(target, classes[target], args.header));
  console.log(`Generated ${relative(Deno.cwd(), outputPath)}`);
}

if (import.meta.main) {
  await main();
}

#!/usr/bin/env -S deno run -A
import { join } from "@std/path";
import { MarkdownLinkTester } from "../lib/deno/doc_links.ts";

async function repoRoot(): Promise<string> {
  const output = await new Deno.Command("git", {
    args: ["rev-parse", "--show-toplevel"],
    stdout: "piped",
    stderr: "null",
  }).output();
  return new TextDecoder().decode(output.stdout).trim() ||
    join(new URL(".", import.meta.url).pathname, "../..");
}

const root = await repoRoot();
const tester = new MarkdownLinkTester({
  repoRoot: root,
  docsDir: join(root, "docs"),
  includeDirs: [
    "01-getting-started",
    "02-core-concepts",
    "03-application-layer",
    "04-network-layer",
    "05-database-layer",
    "06-authentication",
    "07-repository-protocol",
    "08-sync-firehose",
    "09-platform-compatibility",
    "10-tutorials",
    "11-reference",
    "12-diagrams",
  ],
  includeRootFiles: ["index.md", "SUMMARY.md", "GLOSSARY.md"],
  verbose: true,
  title: "PDS IMPLEMENTATION GUIDE - LINK TESTING RESULTS",
});

await tester.testAll();
Deno.exit(tester.printResults() ? 0 : 1);

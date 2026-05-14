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
  title: "LINK TESTING RESULTS",
});

await tester.testAll();
Deno.exit(tester.printResults() ? 0 : 1);

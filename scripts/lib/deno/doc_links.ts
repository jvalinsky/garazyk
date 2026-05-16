import { join, relative, resolve } from "jsr:@std/path@1";

export interface LinkCheckOptions {
  docsDir: string;
  repoRoot: string;
  includeDirs?: string[];
  includeRootFiles?: string[];
  verbose?: boolean;
  title?: string;
}

const linkPattern = /\[([^\]]+)\]\(([^)]+)\)/g;

export class MarkdownLinkTester {
  errors: string[] = [];
  warnings: string[] = [];
  checkedFiles = new Set<string>();

  constructor(private options: LinkCheckOptions) {}

  private relRepo(path: string): string {
    return relative(this.options.repoRoot, path).replaceAll("\\", "/");
  }

  private logError(filePath: string, line: number, message: string) {
    this.errors.push(`${filePath}:${line}: ERROR: ${message}`);
  }

  private logWarning(filePath: string, line: number, message: string) {
    this.warnings.push(`${filePath}:${line}: WARNING: ${message}`);
  }

  private shouldCheckFile(path: string): boolean {
    if (!this.options.includeDirs && !this.options.includeRootFiles) {
      return true;
    }
    const rel = relative(this.options.docsDir, path).replaceAll("\\", "/");
    if (this.options.includeRootFiles?.includes(rel)) return true;
    const [first] = rel.split("/");
    return Boolean(first && this.options.includeDirs?.includes(first));
  }

  private extractMarkdownLinks(
    content: string,
  ): Array<[number, string, string]> {
    const links: Array<[number, string, string]> = [];
    const lines = content.split("\n");
    for (let i = 0; i < lines.length; i++) {
      for (const match of lines[i].matchAll(linkPattern)) {
        links.push([i + 1, match[1], match[2]]);
      }
    }
    return links;
  }

  private extractAnchors(content: string): Set<string> {
    const anchors = new Set<string>();
    for (const line of content.split("\n")) {
      const match = line.match(/^#+\s+(.+)$/);
      if (!match) continue;
      const anchor = match[1].toLowerCase().replace(/[^\w\s-]/g, "").replace(
        /\s+/g,
        "-",
      );
      anchors.add(anchor);
    }
    return anchors;
  }

  private resolveLink(
    sourceFile: string,
    href: string,
  ): { path: string; anchor?: string } | null {
    const [pathPartRaw, anchor] = href.split("#", 2);
    const pathPart = decodeURIComponent(pathPartRaw || "");
    if (/^(https?:|mailto:|tel:|ftp:|data:)/i.test(pathPart)) return null;
    const resolved = pathPart ? resolve(join(sourceFile, "..", pathPart)) : sourceFile;
    return { path: resolved, anchor };
  }

  private async fileExists(path: string): Promise<boolean> {
    try {
      const stat = await Deno.stat(path);
      return stat.isFile;
    } catch {
      return false;
    }
  }

  private async testLink(sourceFile: string, line: number, href: string) {
    if (/^(https?:|mailto:|tel:|ftp:|data:)/i.test(href)) return;
    const target = this.resolveLink(sourceFile, href);
    if (!target) return;

    let targetPath = target.path;
    let exists = await this.fileExists(targetPath);
    if (!exists && !targetPath.split(/[/\\]/).pop()?.includes(".")) {
      if (await this.fileExists(targetPath + ".md")) {
        targetPath += ".md";
        exists = true;
      } else if (await this.fileExists(join(targetPath, "index.md"))) {
        targetPath = join(targetPath, "index.md");
        exists = true;
      }
    }

    if (!exists) {
      this.logError(
        this.relRepo(sourceFile),
        line,
        `Broken link: '${href}' -> target file not found: ${targetPath}`,
      );
      return;
    }

    if (target.anchor && targetPath.endsWith(".md")) {
      try {
        const targetContent = await Deno.readTextFile(targetPath);
        const anchors = this.extractAnchors(targetContent);
        if (!anchors.has(target.anchor)) {
          this.logError(
            this.relRepo(sourceFile),
            line,
            `Broken anchor: '${href}' -> anchor '#${target.anchor}' not found in ${
              targetPath.split("/").at(-1)
            }`,
          );
        }
      } catch (exc) {
        this.logWarning(
          this.relRepo(sourceFile),
          line,
          `Could not read target file: ${exc}`,
        );
      }
    }
  }

  private async testFile(path: string) {
    if (this.checkedFiles.has(path)) return;
    this.checkedFiles.add(path);
    let content = "";
    try {
      content = await Deno.readTextFile(path);
    } catch (exc) {
      this.logError(this.relRepo(path), 0, `Could not read file: ${exc}`);
      return;
    }
    for (const [line, _text, href] of this.extractMarkdownLinks(content)) {
      await this.testLink(path, line, href);
    }
  }

  private async *walkMarkdown(dir: string): AsyncGenerator<string> {
    for await (const entry of Deno.readDir(dir)) {
      const path = join(dir, entry.name);
      if (entry.isDirectory) {
        yield* this.walkMarkdown(path);
      } else if (
        entry.isFile && entry.name.endsWith(".md") && this.shouldCheckFile(path)
      ) {
        yield path;
      }
    }
  }

  async testAll() {
    const files: string[] = [];
    for await (const file of this.walkMarkdown(this.options.docsDir)) {
      files.push(file);
    }
    files.sort();
    console.log(`Testing ${files.length} markdown files...`);
    for (const file of files) {
      if (this.options.verbose) {
        console.log(
          `  Checking ${relative(this.options.docsDir, file).replaceAll("\\", "/")}`,
        );
      }
      await this.testFile(file);
    }
  }

  printResults(): boolean {
    console.log(`\n${"=".repeat(80)}`);
    console.log(this.options.title || "LINK TESTING RESULTS");
    console.log("=".repeat(80));

    if (this.errors.length > 0) {
      console.log(`\nFound ${this.errors.length} errors:\n`);
      for (const error of this.errors) console.log(`  ${error}`);
    } else {
      console.log("\nNo errors found.");
    }

    if (this.warnings.length > 0) {
      console.log(`\nFound ${this.warnings.length} warnings:\n`);
      for (const warning of this.warnings) console.log(`  ${warning}`);
    }

    console.log(`\nChecked ${this.checkedFiles.size} files`);
    console.log("=".repeat(80));
    return this.errors.length === 0;
  }
}

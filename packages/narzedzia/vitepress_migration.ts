/**
 * VitePress Documentation Migration Tool.
 *
 * Converts Jekyll documentation to VitePress format while preserving
 * all content. Handles front matter conversion, link format updates,
 * diagram migration, and backup creation.
 *
 * Rewritten from Node.js to Deno APIs.
 *
 * @module narzedzia/vitepress-migration
 */

import { dirname, join, relative } from "@std/path";

// ============================================================================
// Interfaces
// ============================================================================

/** Options for the VitePress migration. */
export interface MigrationOptions {
  /** Source directory containing Jekyll docs. */
  sourceDir: string;
  /** Target directory for VitePress docs. */
  targetDir: string;
  /** Backup directory for pre-migration snapshots. */
  backupDir: string;
  /** If true, run without making changes. */
  dryRun: boolean;
}

/** Result of a VitePress migration run. */
export interface MigrationResult {
  /** Total files examined. */
  filesProcessed: number;
  /** Files that were actually converted. */
  filesConverted: number;
  /** Number of links updated from .md to extensionless. */
  linkUpdates: number;
  /** Errors encountered during migration. */
  errors: MigrationError[];
  /** Non-fatal warnings. */
  warnings: string[];
}

/** A single error during migration. */
export interface MigrationError {
  /** Category of the error. */
  type: "file" | "content" | "link" | "diagram";
  /** File where the error occurred. */
  file: string;
  /** Line number, if applicable. */
  line?: number;
  /** Human-readable error message. */
  message: string;
}

/** Metadata for a discovered Markdown file. */
export interface FileInfo {
  /** Absolute path to the file. */
  path: string;
  /** Path relative to the source directory. */
  relativePath: string;
  /** File content. */
  content: string;
  /** Whether the file is Markdown. */
  isMarkdown: boolean;
}

// ============================================================================
// Migration Tool Class
// ============================================================================

/**
 * Tool for migrating Jekyll documentation to VitePress format.
 *
 * Handles front matter conversion (removing Jekyll-specific fields),
 * link format updates (`.md` → extensionless), diagram copying,
 * and backup creation.
 *
 * @example
 * ```ts
 * const tool = new MigrationTool({
 *   sourceDir: "docs/",
 *   targetDir: "docs/",
 *   backupDir: "docs/archive/migration-backup/",
 *   dryRun: false,
 * });
 * const result = await tool.migrate();
 * ```
 */
export class MigrationTool {
  private options: MigrationOptions;
  private result: MigrationResult;

  constructor(options: MigrationOptions) {
    this.options = options;
    this.result = {
      filesProcessed: 0,
      filesConverted: 0,
      linkUpdates: 0,
      errors: [],
      warnings: [],
    };
  }

  /**
   * Execute the migration process.
   *
   * Validates the source directory, creates a backup, discovers Markdown
   * files, processes each one, copies diagrams, and generates a report.
   *
   * @returns The migration result with counts and any errors/warnings
   */
  async migrate(): Promise<MigrationResult> {
    console.log("Starting VitePress migration...\n");

    try {
      this.validateSourceDirectory();
      await this.createBackup();
      const files = this.discoverMarkdownFiles();
      console.log(`Found ${files.length} Markdown files\n`);

      for (const file of files) {
        await this.processFile(file);
      }

      await this.copyDiagrams();
      this.generateReport();

      console.log("\nMigration complete!");
    } catch (error) {
      console.error("\nMigration failed:", error);
      this.result.errors.push({
        type: "file",
        file: "migration",
        message: error instanceof Error ? error.message : String(error),
      });
    }

    return this.result;
  }

  /** Validate that source directory exists and is readable. */
  private validateSourceDirectory(): void {
    try {
      const stat = Deno.statSync(this.options.sourceDir);
      if (!stat.isDirectory) {
        throw new Error(
          `Source path is not a directory: ${this.options.sourceDir}`,
        );
      }
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw new Error(
          `Source directory not found: ${this.options.sourceDir}`,
        );
      }
      throw error;
    }
    console.log(`Source directory validated: ${this.options.sourceDir}`);
  }

  /** Create backup of source files before migration. */
  private async createBackup(): Promise<void> {
    if (this.options.dryRun) {
      console.log(
        `[DRY RUN] Would create backup at: ${this.options.backupDir}`,
      );
      return;
    }

    if (this.options.sourceDir === this.options.targetDir) {
      console.log(`Creating backup at: ${this.options.backupDir}`);

      try {
        await Deno.remove(this.options.backupDir, { recursive: true });
      } catch {
        // No existing backup is fine.
      }

      await Deno.mkdir(this.options.backupDir, { recursive: true });
      await this.copyDirectory(this.options.sourceDir, this.options.backupDir);

      console.log("Backup created successfully\n");
    } else {
      console.log("Skipping backup (source and target are different)\n");
    }
  }

  /** Recursively copy a directory, skipping node_modules/.vitepress/.git. */
  private async copyDirectory(
    source: string,
    destination: string,
  ): Promise<void> {
    await Deno.mkdir(destination, { recursive: true });

    for await (const entry of Deno.readDir(source)) {
      const sourcePath = join(source, entry.name);
      const destPath = join(destination, entry.name);

      if (entry.isDirectory) {
        if (
          entry.name === "node_modules" || entry.name === ".vitepress" ||
          entry.name === ".git"
        ) {
          continue;
        }
        await this.copyDirectory(sourcePath, destPath);
      } else {
        await Deno.copyFile(sourcePath, destPath);
      }
    }
  }

  /** Discover all Markdown files in source directory. */
  private discoverMarkdownFiles(): FileInfo[] {
    const files: FileInfo[] = [];

    const walkDirectory = (dir: string): void => {
      for (const entry of Deno.readDirSync(dir)) {
        const fullPath = join(dir, entry.name);

        if (entry.isDirectory) {
          if (
            entry.name === "node_modules" || entry.name === ".vitepress" ||
            entry.name === ".git"
          ) {
            continue;
          }
          walkDirectory(fullPath);
        } else if (entry.isFile && entry.name.endsWith(".md")) {
          const relPath = relative(this.options.sourceDir, fullPath);
          const content = Deno.readTextFileSync(fullPath);

          files.push({
            path: fullPath,
            relativePath: relPath,
            content,
            isMarkdown: true,
          });
        }
      }
    };

    walkDirectory(this.options.sourceDir);
    return files;
  }

  /** Process a single file: convert front matter and update links. */
  private async processFile(file: FileInfo): Promise<void> {
    this.result.filesProcessed++;

    try {
      let content = file.content;
      let modified = false;

      const frontMatterResult = this.convertFrontMatter(content);
      if (frontMatterResult.modified) {
        content = frontMatterResult.content;
        modified = true;
      }

      const linkResult = this.updateLinks(content);
      if (linkResult.modified) {
        content = linkResult.content;
        this.result.linkUpdates += linkResult.count;
        modified = true;
      }

      if (modified) {
        this.result.filesConverted++;

        if (!this.options.dryRun) {
          const targetPath = join(this.options.targetDir, file.relativePath);
          const targetDir = dirname(targetPath);
          await Deno.mkdir(targetDir, { recursive: true });
          await Deno.writeTextFile(targetPath, content);
        }

        console.log(`Converted: ${file.relativePath}`);
      } else {
        console.log(`  Skipped: ${file.relativePath} (no changes needed)`);
      }
    } catch (error) {
      this.result.errors.push({
        type: "file",
        file: file.relativePath,
        message: error instanceof Error ? error.message : String(error),
      });
      console.error(`Error processing ${file.relativePath}:`, error);
    }
  }

  /**
   * Convert Jekyll front matter to VitePress format.
   *
   * Removes Jekyll-specific fields like `layout:` and cleans up
   * empty lines in the front matter block.
   */
  convertFrontMatter(content: string): { content: string; modified: boolean } {
    const frontMatterRegex = /^---\n([\s\S]*?)\n---\n/;
    const match = content.match(frontMatterRegex);

    if (!match) {
      return { content, modified: false };
    }

    const frontMatter = match[1];
    let modified = false;
    let newFrontMatter = frontMatter;

    if (frontMatter.includes("layout:")) {
      newFrontMatter = newFrontMatter.replace(/^layout:.*$/m, "");
      modified = true;
    }

    newFrontMatter = newFrontMatter.split("\n")
      .filter((line) => line.trim() !== "")
      .join("\n");

    if (modified) {
      const newContent = content.replace(
        frontMatterRegex,
        `---\n${newFrontMatter}\n---\n`,
      );
      return { content: newContent, modified: true };
    }

    return { content, modified: false };
  }

  /**
   * Update links from Jekyll format to VitePress format.
   *
   * Converts `.md` links to extensionless links (VitePress convention),
   * preserving anchors.
   */
  updateLinks(
    content: string,
  ): { content: string; modified: boolean; count: number } {
    let modified = false;
    let count = 0;

    const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;

    const newContent = content.replace(linkRegex, (match, text, url) => {
      if (url.includes("://") || !url.includes(".md")) {
        return match;
      }

      const [pathPart, anchor] = url.split("#");
      let newUrl = pathPart.replace(/\.md$/, "");

      if (anchor) {
        newUrl += `#${anchor}`;
      }

      if (newUrl !== url) {
        modified = true;
        count++;
        return `[${text}](${newUrl})`;
      }

      return match;
    });

    return { content: newContent, modified, count };
  }

  /** Copy SVG diagrams to public directory. */
  private async copyDiagrams(): Promise<void> {
    const diagramsSource = join(this.options.sourceDir, "12-diagrams");
    const diagramsTarget = join(this.options.targetDir, "public", "diagrams");

    try {
      const stat = await Deno.stat(diagramsSource);
      if (!stat.isDirectory) {
        this.result.warnings.push("Diagrams directory not found: 12-diagrams/");
        return;
      }
    } catch {
      this.result.warnings.push("Diagrams directory not found: 12-diagrams/");
      return;
    }

    console.log("\nCopying diagrams...");

    if (this.options.dryRun) {
      console.log(
        `[DRY RUN] Would copy diagrams from ${diagramsSource} to ${diagramsTarget}`,
      );
      return;
    }

    await Deno.mkdir(diagramsTarget, { recursive: true });

    let copiedCount = 0;
    for await (const entry of Deno.readDir(diagramsSource)) {
      if (entry.isFile && entry.name.endsWith(".svg")) {
        const sourcePath = join(diagramsSource, entry.name);
        const targetPath = join(diagramsTarget, entry.name);
        await Deno.copyFile(sourcePath, targetPath);
        copiedCount++;
      }
    }

    console.log(`Copied ${copiedCount} diagram files`);
  }

  /** Generate migration report to console and file. */
  generateReport(): void {
    console.log("\n" + "=".repeat(60));
    console.log("MIGRATION REPORT");
    console.log("=".repeat(60));
    console.log(`Files processed:  ${this.result.filesProcessed}`);
    console.log(`Files converted:  ${this.result.filesConverted}`);
    console.log(`Links updated:    ${this.result.linkUpdates}`);
    console.log(`Errors:           ${this.result.errors.length}`);
    console.log(`Warnings:         ${this.result.warnings.length}`);
    console.log("=".repeat(60));

    if (this.result.errors.length > 0) {
      console.log("\nERRORS:");
      for (const error of this.result.errors) {
        console.log(`  - ${error.file}: ${error.message}`);
      }
    }

    if (this.result.warnings.length > 0) {
      console.log("\nWARNINGS:");
      for (const warning of this.result.warnings) {
        console.log(`  - ${warning}`);
      }
    }

    if (!this.options.dryRun) {
      const reportPath = join(this.options.targetDir, "migration-report.md");
      const reportContent = this.generateReportMarkdown();
      Deno.writeTextFileSync(reportPath, reportContent);
      console.log(`\nReport saved to: ${reportPath}`);
    }
  }

  /** Generate Markdown report content. */
  private generateReportMarkdown(): string {
    const timestamp = new Date().toISOString();

    let report = `# VitePress Migration Report\n\n`;
    report += `**Generated:** ${timestamp}\n\n`;
    report += `## Summary\n\n`;
    report += `- **Files Processed:** ${this.result.filesProcessed}\n`;
    report += `- **Files Converted:** ${this.result.filesConverted}\n`;
    report += `- **Links Updated:** ${this.result.linkUpdates}\n`;
    report += `- **Errors:** ${this.result.errors.length}\n`;
    report += `- **Warnings:** ${this.result.warnings.length}\n\n`;

    if (this.result.errors.length > 0) {
      report += `## Errors\n\n`;
      for (const error of this.result.errors) {
        report += `- **${error.file}**: ${error.message}\n`;
      }
      report += `\n`;
    }

    if (this.result.warnings.length > 0) {
      report += `## Warnings\n\n`;
      for (const warning of this.result.warnings) {
        report += `- ${warning}\n`;
      }
      report += `\n`;
    }

    report += `## Migration Options\n\n`;
    report += `- **Source Directory:** ${this.options.sourceDir}\n`;
    report += `- **Target Directory:** ${this.options.targetDir}\n`;
    report += `- **Backup Directory:** ${this.options.backupDir}\n`;
    report += `- **Dry Run:** ${this.options.dryRun}\n`;

    return report;
  }
}

// ============================================================================
// CLI Entry Point
// ============================================================================

export async function main(): Promise<void> {
  const args = Deno.args;

  const options: MigrationOptions = {
    sourceDir: "docs/",
    targetDir: "docs/",
    backupDir: "docs/archive/migration-backup/",
    dryRun: false,
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--source":
        options.sourceDir = args[++i];
        break;
      case "--target":
        options.targetDir = args[++i];
        break;
      case "--backup":
        options.backupDir = args[++i];
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--help":
        console.log(`
VitePress Documentation Migration Tool

Usage:
  deno run -A @garazyk/narzedzia/vitepress-migration [options]

Options:
  --source <dir>    Source directory (default: docs/)
  --target <dir>    Target directory (default: docs/)
  --backup <dir>    Backup directory (default: docs/archive/migration-backup/)
  --dry-run         Run without making changes
  --help            Show this help message
        `);
        Deno.exit(0);
    }
  }

  const tool = new MigrationTool(options);
  const result = await tool.migrate();

  if (result.errors.length > 0) {
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}

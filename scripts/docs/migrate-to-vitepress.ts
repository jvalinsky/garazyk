#!/usr/bin/env tsx
/**
 * VitePress Documentation Migration Tool
 * 
 * Converts Jekyll documentation to VitePress format while preserving all content.
 * 
 * Features:
 * - Front matter conversion (Jekyll → VitePress)
 * - Link format updates (.md → extensionless)
 * - Diagram migration and reference updates
 * - Backup mechanism for source files
 * - Comprehensive migration reporting
 * 
 * Usage:
 *   tsx scripts/migrate-to-vitepress.ts [options]
 * 
 * Options:
 *   --source <dir>    Source directory (default: docs/)
 *   --target <dir>    Target directory (default: docs/)
 *   --backup <dir>    Backup directory (default: docs/archive/migration-backup/)
 *   --dry-run         Run without making changes
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

// Get __dirname equivalent in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================================
// Interfaces
// ============================================================================

interface MigrationOptions {
  sourceDir: string;      // 'docs/'
  targetDir: string;      // 'docs/' (in-place migration)
  backupDir: string;      // 'docs/archive/migration-backup/'
  dryRun: boolean;
}

interface MigrationResult {
  filesProcessed: number;
  filesConverted: number;
  linkUpdates: number;
  errors: MigrationError[];
  warnings: string[];
}

interface MigrationError {
  type: 'file' | 'content' | 'link' | 'diagram';
  file: string;
  line?: number;
  message: string;
}

interface FileInfo {
  path: string;
  relativePath: string;
  content: string;
  isMarkdown: boolean;
}

// ============================================================================
// Migration Tool Class
// ============================================================================

class MigrationTool {
  private options: MigrationOptions;
  private result: MigrationResult;

  constructor(options: MigrationOptions) {
    this.options = options;
    this.result = {
      filesProcessed: 0,
      filesConverted: 0,
      linkUpdates: 0,
      errors: [],
      warnings: []
    };
  }

  /**
   * Execute the migration process
   */
  async migrate(): Promise<MigrationResult> {
    console.log('🚀 Starting VitePress migration...\n');
    
    try {
      // Step 1: Validate source directory
      this.validateSourceDirectory();
      
      // Step 2: Create backup
      await this.createBackup();
      
      // Step 3: Discover all Markdown files
      const files = this.discoverMarkdownFiles();
      console.log(`📄 Found ${files.length} Markdown files\n`);
      
      // Step 4: Process each file
      for (const file of files) {
        await this.processFile(file);
      }
      
      // Step 5: Copy diagrams
      await this.copyDiagrams();
      
      // Step 6: Generate report
      this.generateReport();
      
      console.log('\n✅ Migration complete!');
      
    } catch (error) {
      console.error('\n❌ Migration failed:', error);
      this.result.errors.push({
        type: 'file',
        file: 'migration',
        message: error instanceof Error ? error.message : String(error)
      });
    }
    
    return this.result;
  }

  /**
   * Validate that source directory exists and is readable
   */
  private validateSourceDirectory(): void {
    if (!fs.existsSync(this.options.sourceDir)) {
      throw new Error(`Source directory not found: ${this.options.sourceDir}`);
    }
    
    const stats = fs.statSync(this.options.sourceDir);
    if (!stats.isDirectory()) {
      throw new Error(`Source path is not a directory: ${this.options.sourceDir}`);
    }
    
    console.log(`✓ Source directory validated: ${this.options.sourceDir}`);
  }

  /**
   * Create backup of source files before migration
   */
  private async createBackup(): Promise<void> {
    if (this.options.dryRun) {
      console.log(`[DRY RUN] Would create backup at: ${this.options.backupDir}`);
      return;
    }
    
    // Only create backup if source and target are the same (in-place migration)
    if (this.options.sourceDir === this.options.targetDir) {
      console.log(`📦 Creating backup at: ${this.options.backupDir}`);
      
      // Remove existing backup if it exists
      if (fs.existsSync(this.options.backupDir)) {
        fs.rmSync(this.options.backupDir, { recursive: true, force: true });
      }
      
      // Create backup directory
      fs.mkdirSync(this.options.backupDir, { recursive: true });
      
      // Copy all files to backup
      this.copyDirectory(this.options.sourceDir, this.options.backupDir);
      
      console.log(`✓ Backup created successfully\n`);
    } else {
      console.log(`ℹ️  Skipping backup (source and target are different)\n`);
    }
  }

  /**
   * Recursively copy directory
   */
  private copyDirectory(source: string, destination: string): void {
    // Create destination directory
    if (!fs.existsSync(destination)) {
      fs.mkdirSync(destination, { recursive: true });
    }
    
    // Read source directory
    const entries = fs.readdirSync(source, { withFileTypes: true });
    
    for (const entry of entries) {
      const sourcePath = path.join(source, entry.name);
      const destPath = path.join(destination, entry.name);
      
      // Skip certain directories
      if (entry.isDirectory()) {
        if (entry.name === 'node_modules' || entry.name === '.vitepress' || entry.name === '.git') {
          continue;
        }
        this.copyDirectory(sourcePath, destPath);
      } else {
        fs.copyFileSync(sourcePath, destPath);
      }
    }
  }

  /**
   * Discover all Markdown files in source directory
   */
  private discoverMarkdownFiles(): FileInfo[] {
    const files: FileInfo[] = [];
    
    const walkDirectory = (dir: string): void => {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        
        if (entry.isDirectory()) {
          // Skip certain directories
          if (entry.name === 'node_modules' || entry.name === '.vitepress' || entry.name === '.git') {
            continue;
          }
          walkDirectory(fullPath);
        } else if (entry.isFile() && entry.name.endsWith('.md')) {
          const relativePath = path.relative(this.options.sourceDir, fullPath);
          const content = fs.readFileSync(fullPath, 'utf-8');
          
          files.push({
            path: fullPath,
            relativePath,
            content,
            isMarkdown: true
          });
        }
      }
    };
    
    walkDirectory(this.options.sourceDir);
    return files;
  }

  /**
   * Process a single file
   */
  private async processFile(file: FileInfo): Promise<void> {
    this.result.filesProcessed++;
    
    try {
      let content = file.content;
      let modified = false;
      
      // Convert front matter
      const frontMatterResult = this.convertFrontMatter(content);
      if (frontMatterResult.modified) {
        content = frontMatterResult.content;
        modified = true;
      }
      
      // Update links
      const linkResult = this.updateLinks(content);
      if (linkResult.modified) {
        content = linkResult.content;
        this.result.linkUpdates += linkResult.count;
        modified = true;
      }
      
      // Write file if modified
      if (modified) {
        this.result.filesConverted++;
        
        if (!this.options.dryRun) {
          const targetPath = path.join(this.options.targetDir, file.relativePath);
          const targetDir = path.dirname(targetPath);
          
          // Ensure target directory exists
          if (!fs.existsSync(targetDir)) {
            fs.mkdirSync(targetDir, { recursive: true });
          }
          
          fs.writeFileSync(targetPath, content, 'utf-8');
        }
        
        console.log(`✓ Converted: ${file.relativePath}`);
      } else {
        console.log(`  Skipped: ${file.relativePath} (no changes needed)`);
      }
      
    } catch (error) {
      this.result.errors.push({
        type: 'file',
        file: file.relativePath,
        message: error instanceof Error ? error.message : String(error)
      });
      console.error(`✗ Error processing ${file.relativePath}:`, error);
    }
  }

  /**
   * Convert Jekyll front matter to VitePress format
   */
  convertFrontMatter(content: string): { content: string; modified: boolean } {
    // Match front matter block
    const frontMatterRegex = /^---\n([\s\S]*?)\n---\n/;
    const match = content.match(frontMatterRegex);
    
    if (!match) {
      // No front matter found - this is okay for some files
      return { content, modified: false };
    }
    
    const frontMatter = match[1];
    let modified = false;
    let newFrontMatter = frontMatter;
    
    // Remove Jekyll-specific fields
    if (frontMatter.includes('layout:')) {
      newFrontMatter = newFrontMatter.replace(/^layout:.*$/m, '');
      modified = true;
    }
    
    // Clean up empty lines
    newFrontMatter = newFrontMatter.split('\n')
      .filter(line => line.trim() !== '')
      .join('\n');
    
    if (modified) {
      const newContent = content.replace(frontMatterRegex, `---\n${newFrontMatter}\n---\n`);
      return { content: newContent, modified: true };
    }
    
    return { content, modified: false };
  }

  /**
   * Update links from Jekyll format to VitePress format
   */
  updateLinks(content: string): { content: string; modified: boolean; count: number } {
    let modified = false;
    let count = 0;
    
    // Match Markdown links: [text](url)
    const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;
    
    const newContent = content.replace(linkRegex, (match, text, url) => {
      // Only process relative links to .md files
      if (url.includes('://') || !url.includes('.md')) {
        return match;
      }
      
      // Remove .md extension but preserve anchors
      const [path, anchor] = url.split('#');
      let newUrl = path.replace(/\.md$/, '');
      
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

  /**
   * Copy SVG diagrams to public directory
   */
  private async copyDiagrams(): Promise<void> {
    const diagramsSource = path.join(this.options.sourceDir, '12-diagrams');
    const diagramsTarget = path.join(this.options.targetDir, 'public', 'diagrams');
    
    if (!fs.existsSync(diagramsSource)) {
      this.result.warnings.push('Diagrams directory not found: 12-diagrams/');
      return;
    }
    
    console.log('\n📊 Copying diagrams...');
    
    if (this.options.dryRun) {
      console.log(`[DRY RUN] Would copy diagrams from ${diagramsSource} to ${diagramsTarget}`);
      return;
    }
    
    // Create target directory
    if (!fs.existsSync(diagramsTarget)) {
      fs.mkdirSync(diagramsTarget, { recursive: true });
    }
    
    // Copy all SVG files
    const files = fs.readdirSync(diagramsSource);
    let copiedCount = 0;
    
    for (const file of files) {
      if (file.endsWith('.svg')) {
        const sourcePath = path.join(diagramsSource, file);
        const targetPath = path.join(diagramsTarget, file);
        fs.copyFileSync(sourcePath, targetPath);
        copiedCount++;
      }
    }
    
    console.log(`✓ Copied ${copiedCount} diagram files`);
  }

  /**
   * Generate migration report
   */
  generateReport(): void {
    console.log('\n' + '='.repeat(60));
    console.log('MIGRATION REPORT');
    console.log('='.repeat(60));
    console.log(`Files processed:  ${this.result.filesProcessed}`);
    console.log(`Files converted:  ${this.result.filesConverted}`);
    console.log(`Links updated:    ${this.result.linkUpdates}`);
    console.log(`Errors:           ${this.result.errors.length}`);
    console.log(`Warnings:         ${this.result.warnings.length}`);
    console.log('='.repeat(60));
    
    if (this.result.errors.length > 0) {
      console.log('\n❌ ERRORS:');
      for (const error of this.result.errors) {
        console.log(`  - ${error.file}: ${error.message}`);
      }
    }
    
    if (this.result.warnings.length > 0) {
      console.log('\n⚠️  WARNINGS:');
      for (const warning of this.result.warnings) {
        console.log(`  - ${warning}`);
      }
    }
    
    // Write report to file
    if (!this.options.dryRun) {
      const reportPath = path.join(this.options.targetDir, 'migration-report.md');
      const reportContent = this.generateReportMarkdown();
      fs.writeFileSync(reportPath, reportContent, 'utf-8');
      console.log(`\n📄 Report saved to: ${reportPath}`);
    }
  }

  /**
   * Generate Markdown report
   */
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

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);
  
  const options: MigrationOptions = {
    sourceDir: 'docs/',
    targetDir: 'docs/',
    backupDir: 'docs/archive/migration-backup/',
    dryRun: false
  };
  
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--source':
        options.sourceDir = args[++i];
        break;
      case '--target':
        options.targetDir = args[++i];
        break;
      case '--backup':
        options.backupDir = args[++i];
        break;
      case '--dry-run':
        options.dryRun = true;
        break;
      case '--help':
        console.log(`
VitePress Documentation Migration Tool

Usage:
  tsx scripts/migrate-to-vitepress.ts [options]

Options:
  --source <dir>    Source directory (default: docs/)
  --target <dir>    Target directory (default: docs/)
  --backup <dir>    Backup directory (default: docs/archive/migration-backup/)
  --dry-run         Run without making changes
  --help            Show this help message
        `);
        process.exit(0);
    }
  }
  
  // Run migration
  const tool = new MigrationTool(options);
  const result = await tool.migrate();
  
  // Exit with error code if there were errors
  if (result.errors.length > 0) {
    process.exit(1);
  }
}

// Run if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

// Export for testing
export { MigrationTool, MigrationOptions, MigrationResult, MigrationError, FileInfo };

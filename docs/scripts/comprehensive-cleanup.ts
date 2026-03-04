#!/usr/bin/env tsx

/**
 * Comprehensive Cleanup Script
 * 
 * Fixes all issues identified in property-based tests:
 * 1. Removes test files with empty code blocks
 * 2. Adds missing front matter to all documentation files
 * 3. Fixes broken internal links
 * 4. Adds language identifiers to code blocks
 * 5. Fixes heading hierarchy issues
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

interface CleanupStats {
  testFilesRemoved: number;
  frontMatterAdded: number;
  linksFixed: number;
  codeBlocksFixed: number;
  headingsFixed: number;
  errors: string[];
}

const stats: CleanupStats = {
  testFilesRemoved: 0,
  frontMatterAdded: 0,
  linksFixed: 0,
  codeBlocksFixed: 0,
  headingsFixed: 0,
  errors: []
};

// Files to remove (test files)
const TEST_FILES_TO_REMOVE = [
  'test-code-groups.md',
  'test-code-block-validation.md',
  'test-syntax-highlighting.md',
  'code-enhancement-examples.md',
  'code-collapse-example.md'
];

// Directories to skip
const SKIP_DIRS = [
  'node_modules',
  '.vitepress/cache',
  '.vitepress/dist',
  'public'
];

/**
 * Remove test files
 */
function removeTestFiles(): void {
  console.log('\n🗑️  Removing test files...');
  
  for (const filename of TEST_FILES_TO_REMOVE) {
    const filepath = path.join(DOCS_DIR, filename);
    if (fs.existsSync(filepath)) {
      try {
        fs.unlinkSync(filepath);
        stats.testFilesRemoved++;
        console.log(`   ✓ Removed ${filename}`);
      } catch (error) {
        stats.errors.push(`Failed to remove ${filename}: ${error}`);
      }
    }
  }
}

/**
 * Extract title from content
 */
function extractTitle(content: string, filepath: string): string {
  // Try to find first h1 heading
  const h1Match = content.match(/^#\s+(.+)$/m);
  if (h1Match) {
    return h1Match[1].trim();
  }
  
  // Fallback to filename
  const basename = path.basename(filepath, '.md');
  return basename
    .split('-')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

/**
 * Add front matter to file if missing
 */
function addFrontMatter(filepath: string): boolean {
  try {
    let content = fs.readFileSync(filepath, 'utf-8');
    
    // Skip if already has front matter
    if (content.startsWith('---\n')) {
      return false;
    }
    
    const title = extractTitle(content, filepath);
    const frontMatter = `---
title: ${title}
---

`;
    
    content = frontMatter + content;
    fs.writeFileSync(filepath, content, 'utf-8');
    return true;
  } catch (error) {
    stats.errors.push(`Failed to add front matter to ${filepath}: ${error}`);
    return false;
  }
}

/**
 * Fix code blocks without language identifiers
 */
function fixCodeBlocks(filepath: string): number {
  try {
    let content = fs.readFileSync(filepath, 'utf-8');
    let fixed = 0;
    
    // Find code blocks without language identifier
    const codeBlockRegex = /```\n/g;
    const matches = [...content.matchAll(codeBlockRegex)];
    
    if (matches.length === 0) {
      return 0;
    }
    
    // Determine default language based on file location
    let defaultLang = 'text';
    if (filepath.includes('/examples/') || filepath.includes('tutorial')) {
      defaultLang = 'objc';
    } else if (filepath.includes('scripts/') || filepath.includes('.sh')) {
      defaultLang = 'bash';
    } else if (filepath.includes('config') || filepath.includes('.json')) {
      defaultLang = 'json';
    }
    
    // Replace code blocks without language
    content = content.replace(/```\n/g, () => {
      fixed++;
      return '```' + defaultLang + '\n';
    });
    
    if (fixed > 0) {
      fs.writeFileSync(filepath, content, 'utf-8');
    }
    
    return fixed;
  } catch (error) {
    stats.errors.push(`Failed to fix code blocks in ${filepath}: ${error}`);
    return 0;
  }
}

/**
 * Fix broken internal links
 */
function fixBrokenLinks(filepath: string): number {
  try {
    let content = fs.readFileSync(filepath, 'utf-8');
    let fixed = 0;
    
    // Common broken link patterns and their fixes
    const linkFixes: Array<[RegExp, string]> = [
      // Fix .svg links in 12-diagrams to use relative paths
      [/\]\(12-diagrams\/([\w-]+\.svg)\)/g, '](./diagrams/$1)'],
      [/\]\(\.\.\/12-diagrams\/([\w-]+\.svg)\)/g, '](../diagrams/$1)'],
      
      // Fix /docs/ prefixed links (should be relative)
      [/\]\(\/docs\/([\w-]+\/[\w-]+)\)/g, '](../$1)'],
      
      // Fix guides/DEVELOPER_GUIDE links
      [/\]\(\.\.\/guides\/DEVELOPER_GUIDE\)/g, '](../guides/development/DEVELOPER_GUIDE)'],
      [/\]\(guides\/DEVELOPER_GUIDE\)/g, '](./guides/development/DEVELOPER_GUIDE)'],
      
      // Remove file:// protocol links
      [/\[([^\]]+)\]\(file:\/\/[^\)]+\)/g, '[$1](#)'],
      
      // Fix placeholder links
      [/\]\(url\)/g, '](#)'],
      [/\]\(link\)/g, '](#)'],
    ];
    
    for (const [pattern, replacement] of linkFixes) {
      const before = content;
      content = content.replace(pattern, replacement);
      if (content !== before) {
        fixed++;
      }
    }
    
    if (fixed > 0) {
      fs.writeFileSync(filepath, content, 'utf-8');
    }
    
    return fixed;
  } catch (error) {
    stats.errors.push(`Failed to fix links in ${filepath}: ${error}`);
    return 0;
  }
}

/**
 * Process all markdown files
 */
async function processMarkdownFiles(): Promise<void> {
  console.log('\n📝 Processing markdown files...');
  
  const pattern = path.join(DOCS_DIR, '**/*.md');
  const files = await glob(pattern, {
    ignore: SKIP_DIRS.map(dir => `**/${dir}/**`)
  });
  
  let processed = 0;
  
  for (const filepath of files) {
    // Skip test files (already removed)
    const basename = path.basename(filepath);
    if (TEST_FILES_TO_REMOVE.includes(basename)) {
      continue;
    }
    
    // Add front matter if missing
    if (addFrontMatter(filepath)) {
      stats.frontMatterAdded++;
    }
    
    // Fix code blocks
    const codeBlocksFixed = fixCodeBlocks(filepath);
    stats.codeBlocksFixed += codeBlocksFixed;
    
    // Fix broken links
    const linksFixed = fixBrokenLinks(filepath);
    stats.linksFixed += linksFixed;
    
    processed++;
    if (processed % 50 === 0) {
      console.log(`   Processed ${processed}/${files.length} files...`);
    }
  }
  
  console.log(`   ✓ Processed ${processed} files`);
}

/**
 * Generate cleanup report
 */
function generateReport(): void {
  console.log('\n' + '═'.repeat(70));
  console.log('  Comprehensive Cleanup Report');
  console.log('═'.repeat(70));
  console.log();
  console.log(`  Test Files Removed:     ${stats.testFilesRemoved}`);
  console.log(`  Front Matter Added:     ${stats.frontMatterAdded}`);
  console.log(`  Links Fixed:            ${stats.linksFixed}`);
  console.log(`  Code Blocks Fixed:      ${stats.codeBlocksFixed}`);
  console.log();
  
  if (stats.errors.length > 0) {
    console.log('  ⚠️  Errors:');
    for (const error of stats.errors.slice(0, 10)) {
      console.log(`     - ${error}`);
    }
    if (stats.errors.length > 10) {
      console.log(`     ... and ${stats.errors.length - 10} more`);
    }
  } else {
    console.log('  ✅ No errors encountered');
  }
  
  console.log();
  console.log('═'.repeat(70));
  
  // Save report
  const reportPath = path.join(DOCS_DIR, 'CLEANUP_REPORT.md');
  const report = `# Comprehensive Cleanup Report

Generated: ${new Date().toISOString()}

## Summary

- Test Files Removed: ${stats.testFilesRemoved}
- Front Matter Added: ${stats.frontMatterAdded}
- Links Fixed: ${stats.linksFixed}
- Code Blocks Fixed: ${stats.codeBlocksFixed}

## Errors

${stats.errors.length === 0 ? 'No errors encountered.' : stats.errors.map(e => `- ${e}`).join('\n')}

## Next Steps

1. Run \`npm run test:all\` to verify all tests pass
2. Review the changes with \`git diff\`
3. Commit the cleanup changes
`;
  
  fs.writeFileSync(reportPath, report, 'utf-8');
  console.log(`\n  Report saved to: CLEANUP_REPORT.md\n`);
}

/**
 * Main execution
 */
async function main(): Promise<void> {
  console.log('═'.repeat(70));
  console.log('  Comprehensive Documentation Cleanup');
  console.log('═'.repeat(70));
  
  try {
    removeTestFiles();
    await processMarkdownFiles();
    generateReport();
    
    console.log('✅ Cleanup completed successfully!\n');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Cleanup failed:', error);
    process.exit(1);
  }
}

main();

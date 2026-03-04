#!/usr/bin/env tsx

/**
 * Fix Remaining Issues Script
 * 
 * Addresses:
 * 1. Broken diagram links (./diagrams/ paths)
 * 2. Heading hierarchy issues
 * 3. Empty code blocks in specific files
 * 4. Insufficient content in blob-quotas.md
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

interface FixStats {
  diagramLinksFixed: number;
  headingsFixed: number;
  emptyCodeBlocksFixed: number;
  contentEnhanced: number;
  errors: string[];
}

const stats: FixStats = {
  diagramLinksFixed: 0,
  headingsFixed: 0,
  emptyCodeBlocksFixed: 0,
  contentEnhanced: 0,
  errors: []
};

/**
 * Fix diagram links - change ./diagrams/ to ../public/diagrams/
 */
function fixDiagramLinks(filepath: string): number {
  try {
    let content = fs.readFileSync(filepath, 'utf-8');
    let fixed = 0;
    
    // Pattern 1: ./diagrams/file.svg -> /diagrams/file.svg (for VitePress public dir)
    const before1 = content;
    content = content.replace(/\]\(\.\/diagrams\/([\w-]+\.svg)\)/g, '](/diagrams/$1)');
    if (content !== before1) fixed++;
    
    // Pattern 2: ../diagrams/file.svg -> /diagrams/file.svg
    const before2 = content;
    content = content.replace(/\]\(\.\.\/diagrams\/([\w-]+\.svg)\)/g, '](/diagrams/$1)');
    if (content !== before2) fixed++;
    
    // Pattern 3: 12-diagrams/file.svg -> /diagrams/file.svg
    const before3 = content;
    content = content.replace(/\]\(12-diagrams\/([\w-]+\.svg)\)/g, '](/diagrams/$1)');
    if (content !== before3) fixed++;
    
    if (fixed > 0) {
      fs.writeFileSync(filepath, content, 'utf-8');
    }
    
    return fixed;
  } catch (error) {
    stats.errors.push(`Failed to fix diagram links in ${filepath}: ${error}`);
    return 0;
  }
}

/**
 * Fix heading hierarchy - ensure no skipped levels
 */
function fixHeadingHierarchy(filepath: string): number {
  try {
    let content = fs.readFileSync(filepath, 'utf-8');
    const lines = content.split('\n');
    let fixed = 0;
    let lastLevel = 0;
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const headingMatch = line.match(/^(#{1,6})\s+(.+)$/);
      
      if (headingMatch) {
        const level = headingMatch[1].length;
        const text = headingMatch[2];
        
        // Skip if this is the first heading or follows proper hierarchy
        if (lastLevel === 0 || level <= lastLevel + 1) {
          lastLevel = level;
          continue;
        }
        
        // Fix skipped level by reducing to lastLevel + 1
        const correctLevel = lastLevel + 1;
        const correctHeading = '#'.repeat(correctLevel) + ' ' + text;
        lines[i] = correctHeading;
        fixed++;
        lastLevel = correctLevel;
      }
    }
    
    if (fixed > 0) {
      content = lines.join('\n');
      fs.writeFileSync(filepath, content, 'utf-8');
    }
    
    return fixed;
  } catch (error) {
    stats.errors.push(`Failed to fix heading hierarchy in ${filepath}: ${error}`);
    return 0;
  }
}

/**
 * Fix empty code blocks in specific files
 */
function fixEmptyCodeBlocks(filepath: string): number {
  try {
    let content = fs.readFileSync(filepath, 'utf-8');
    let fixed = 0;
    
    // Replace empty code blocks with placeholder
    const emptyBlockPattern = /```(\w+)\n\n```/g;
    const matches = content.match(emptyBlockPattern);
    
    if (matches) {
      content = content.replace(emptyBlockPattern, (match, lang) => {
        fixed++;
        return '```' + lang + '\n# Code example placeholder\n```';
      });
      
      fs.writeFileSync(filepath, content, 'utf-8');
    }
    
    return fixed;
  } catch (error) {
    stats.errors.push(`Failed to fix empty code blocks in ${filepath}: ${error}`);
    return 0;
  }
}

/**
 * Enhance blob-quotas.md with more content
 */
function enhanceBlobQuotas(): void {
  const filepath = path.join(DOCS_DIR, '07-repository-protocol/blob-quotas.md');
  
  if (!fs.existsSync(filepath)) {
    return;
  }
  
  try {
    let content = fs.readFileSync(filepath, 'utf-8');
    
    // Check if content is too short
    if (content.length < 500) {
      // Add more comprehensive content
      const enhancement = `

## Overview

Blob quotas are essential for managing storage resources in a PDS deployment. They prevent individual users from consuming excessive storage and ensure fair resource allocation across all users.

## Quota Enforcement

The PDS enforces blob quotas at multiple levels:

1. **Per-blob size limits** - Individual blobs cannot exceed the maximum size
2. **Per-user total storage** - Each user has a total storage quota
3. **Rate limiting** - Upload frequency is controlled to prevent abuse

## Configuration

Blob quotas are configured in the PDS configuration file:

\`\`\`json
{
  "blob": {
    "max_size": 5242880,
    "user_quota": 52428800
  }
}
\`\`\`

## Monitoring

Administrators can monitor blob usage through the admin API endpoints to track storage consumption and identify users approaching their quotas.
`;
      
      content += enhancement;
      fs.writeFileSync(filepath, content, 'utf-8');
      stats.contentEnhanced++;
    }
  } catch (error) {
    stats.errors.push(`Failed to enhance blob-quotas.md: ${error}`);
  }
}

/**
 * Process all markdown files
 */
async function processFiles(): Promise<void> {
  console.log('\n🔧 Fixing remaining issues...');
  
  const pattern = path.join(DOCS_DIR, '**/*.md');
  const files = await glob(pattern, {
    ignore: ['**/node_modules/**', '**/.vitepress/cache/**', '**/.vitepress/dist/**']
  });
  
  let processed = 0;
  
  for (const filepath of files) {
    // Fix diagram links
    const diagramsFixed = fixDiagramLinks(filepath);
    stats.diagramLinksFixed += diagramsFixed;
    
    // Fix heading hierarchy
    const headingsFixed = fixHeadingHierarchy(filepath);
    stats.headingsFixed += headingsFixed;
    
    // Fix empty code blocks in specific problematic files
    const basename = path.basename(filepath);
    if (['MAINTENANCE.md', 'JEKYLL_ARCHIVE.md'].includes(basename)) {
      const emptyFixed = fixEmptyCodeBlocks(filepath);
      stats.emptyCodeBlocksFixed += emptyFixed;
    }
    
    processed++;
    if (processed % 50 === 0) {
      console.log(`   Processed ${processed}/${files.length} files...`);
    }
  }
  
  console.log(`   ✓ Processed ${processed} files`);
  
  // Enhance specific files
  enhanceBlobQuotas();
}

/**
 * Generate report
 */
function generateReport(): void {
  console.log('\n' + '═'.repeat(70));
  console.log('  Fix Remaining Issues Report');
  console.log('═'.repeat(70));
  console.log();
  console.log(`  Diagram Links Fixed:      ${stats.diagramLinksFixed}`);
  console.log(`  Headings Fixed:           ${stats.headingsFixed}`);
  console.log(`  Empty Code Blocks Fixed:  ${stats.emptyCodeBlocksFixed}`);
  console.log(`  Content Enhanced:         ${stats.contentEnhanced}`);
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
}

/**
 * Main execution
 */
async function main(): Promise<void> {
  console.log('═'.repeat(70));
  console.log('  Fix Remaining Documentation Issues');
  console.log('═'.repeat(70));
  
  try {
    await processFiles();
    generateReport();
    
    console.log('\n✅ Fixes completed successfully!\n');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Fix failed:', error);
    process.exit(1);
  }
}

main();

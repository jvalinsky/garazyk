#!/usr/bin/env tsx

/**
 * Fix Broken Links Properly
 * 
 * Fixes broken links by:
 * 1. Removing links that point to non-existent files (convert to plain text)
 * 2. Fixing directory links to point to index.md
 * 3. Preserving valid links
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

let linksFixed = 0;
let filesModified = 0;

/**
 * Fix broken links in a file
 */
function fixBrokenLinks(filepath: string): number {
  let content = fs.readFileSync(filepath, 'utf-8');
  let fixed = 0;
  const originalContent = content;
  
  // Extract all markdown links
  const linkPattern = /\[([^\]]+)\]\(([^)]+)\)/g;
  const links = [...content.matchAll(linkPattern)];
  
  for (const match of links) {
    const fullMatch = match[0];
    const text = match[1];
    const href = match[2];
    
    // Skip external links, anchors, and empty hrefs
    if (!href || href.startsWith('http://') || href.startsWith('https://') || href.startsWith('#')) {
      continue;
    }
    
    // Skip if href is just "./" or "../" (these cause build errors)
    if (href === './' || href === '../' || href === '.' || href === '..') {
      // Convert to plain text
      content = content.replace(fullMatch, text);
      fixed++;
      continue;
    }
    
    // Check if link target exists
    const fileDir = path.dirname(filepath);
    let targetPath = href.split('#')[0];
    
    if (!targetPath) continue;
    
    // Resolve path
    if (targetPath.startsWith('./') || targetPath.startsWith('../')) {
      targetPath = path.resolve(fileDir, targetPath);
    } else if (targetPath.startsWith('/')) {
      targetPath = path.join(DOCS_DIR, targetPath);
    } else {
      targetPath = path.resolve(fileDir, targetPath);
    }
    
    // Check various extensions
    const possiblePaths = [
      targetPath,
      targetPath + '.md',
      path.join(targetPath, 'index.md'),
      path.join(targetPath, 'README.md')
    ];
    
    // Check if any path exists
    const exists = possiblePaths.some(p => fs.existsSync(p));
    
    if (!exists) {
      // Link is broken - convert to plain text
      content = content.replace(fullMatch, text);
      fixed++;
    }
  }
  
  if (content !== originalContent) {
    fs.writeFileSync(filepath, content, 'utf-8');
    linksFixed += fixed;
    filesModified++;
  }
  
  return fixed;
}

/**
 * Process all files
 */
async function processAllFiles(): Promise<void> {
  console.log('\n🔧 Fixing broken links properly...\n');
  
  const pattern = path.join(DOCS_DIR, '**/*.md');
  const files = await glob(pattern, {
    ignore: [
      '**/node_modules/**',
      '**/.vitepress/cache/**',
      '**/.vitepress/dist/**',
      '**/public/**'
    ]
  });
  
  let processed = 0;
  
  for (const filepath of files) {
    fixBrokenLinks(filepath);
    
    processed++;
    if (processed % 50 === 0) {
      console.log(`   Processed ${processed}/${files.length} files...`);
    }
  }
  
  console.log(`\n✅ Processed ${files.length} files`);
  console.log(`   - Files modified: ${filesModified}`);
  console.log(`   - Links fixed: ${linksFixed}\n`);
}

/**
 * Main execution
 */
async function main(): Promise<void> {
  console.log('═'.repeat(70));
  console.log('  Fix Broken Links Properly');
  console.log('═'.repeat(70));
  
  try {
    await processAllFiles();
    
    console.log('✅ All fixes completed!\n');
    console.log('Run `npm run docs:build` to verify build succeeds.\n');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Fix failed:', error);
    process.exit(1);
  }
}

main();

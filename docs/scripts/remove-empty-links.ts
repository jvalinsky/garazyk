#!/usr/bin/env tsx

/**
 * Remove Empty Links
 * 
 * Removes or fixes links that point to:
 * - Just "./" (empty directory reference)
 * - Just "../" (parent directory reference)
 * - Empty targets
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
 * Remove empty links in a file
 */
function removeEmptyLinks(filepath: string): number {
  let content = fs.readFileSync(filepath, 'utf-8');
  const originalContent = content;
  let fixed = 0;
  
  // Pattern 1: Links with just "./" or "../" or "." or ".."
  const emptyPatterns = [
    /\[([^\]]+)\]\(\.\/\)/g,
    /\[([^\]]+)\]\(\.\.\/\)/g,
    /\[([^\]]+)\]\(\.\)/g,
    /\[([^\]]+)\]\(\.\.\)/g,
    /\[([^\]]+)\]\(\)/g
  ];
  
  for (const pattern of emptyPatterns) {
    const matches = [...content.matchAll(pattern)];
    for (const match of matches) {
      const fullMatch = match[0];
      const text = match[1];
      
      // Convert link to plain text
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
  console.log('\n🔧 Removing empty links...\n');
  
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
    removeEmptyLinks(filepath);
    
    processed++;
    if (processed % 50 === 0) {
      console.log(`   Processed ${processed}/${files.length} files...`);
    }
  }
  
  console.log(`\n✅ Processed ${files.length} files`);
  console.log(`   - Files modified: ${filesModified}`);
  console.log(`   - Links removed: ${linksFixed}\n`);
}

/**
 * Main execution
 */
async function main(): Promise<void> {
  console.log('═'.repeat(70));
  console.log('  Remove Empty Links');
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

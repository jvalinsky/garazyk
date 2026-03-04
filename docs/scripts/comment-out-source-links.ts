#!/usr/bin/env tsx

/**
 * Comment Out Source Code Links
 * 
 * Comments out links to source files outside the docs directory
 * (e.g., ../../ATProtoPDS/Sources/...)
 * These cause VitePress build failures and won't work in deployed docs anyway
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

let linksCommented = 0;
let filesModified = 0;

/**
 * Comment out source code links in a file
 */
function commentOutSourceLinks(filepath: string): number {
  let content = fs.readFileSync(filepath, 'utf-8');
  const originalContent = content;
  let fixed = 0;
  
  // Pattern: Links to ../../ATProtoPDS/ or ../../Sources/
  const sourcePattern = /\[([^\]]+)\]\((\.\.\/\.\.\/(?:ATProtoPDS|Sources)\/[^)]+)\)/g;
  const matches = [...content.matchAll(sourcePattern)];
  
  for (const match of matches) {
    const fullMatch = match[0];
    const text = match[1];
    const href = match[2];
    
    // Comment it out with HTML comment
    const replacement = `<!-- [${text}](${href}) -->`;
    content = content.replace(fullMatch, replacement);
    fixed++;
  }
  
  if (content !== originalContent) {
    fs.writeFileSync(filepath, content, 'utf-8');
    linksCommented += fixed;
    filesModified++;
  }
  
  return fixed;
}

/**
 * Process all files
 */
async function processAllFiles(): Promise<void> {
  console.log('\n🔧 Commenting out source code links...\n');
  
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
    commentOutSourceLinks(filepath);
    
    processed++;
    if (processed % 50 === 0) {
      console.log(`   Processed ${processed}/${files.length} files...`);
    }
  }
  
  console.log(`\n✅ Processed ${files.length} files`);
  console.log(`   - Files modified: ${filesModified}`);
  console.log(`   - Links commented: ${linksCommented}\n`);
}

/**
 * Main execution
 */
async function main(): Promise<void> {
  console.log('═'.repeat(70));
  console.log('  Comment Out Source Code Links');
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

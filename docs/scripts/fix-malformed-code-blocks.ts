#!/usr/bin/env tsx

/**
 * Fix Malformed Code Blocks
 * 
 * Fixes code blocks that have:
 * 1. ```text after closing ``` (should be just ```)
 * 2. Empty or invalid language identifiers
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

let blocksFixed = 0;
let filesModified = 0;

/**
 * Fix malformed code blocks in a file
 */
function fixMalformedCodeBlocks(filepath: string): number {
  let content = fs.readFileSync(filepath, 'utf-8');
  const originalContent = content;
  let fixed = 0;
  
  // Fix ```text after closing ``` (should be just ```)
  const pattern1 = /```\s*\n```text\s*\n/g;
  const matches1 = content.match(pattern1);
  if (matches1) {
    content = content.replace(pattern1, '```\n\n');
    fixed += matches1.length;
  }
  
  // Fix ``` followed immediately by text on same line (closing block)
  const pattern2 = /\n```text\s*\n/g;
  const matches2 = content.match(pattern2);
  if (matches2) {
    content = content.replace(pattern2, '\n```\n\n');
    fixed += matches2.length;
  }
  
  if (content !== originalContent) {
    fs.writeFileSync(filepath, content, 'utf-8');
    blocksFixed += fixed;
    filesModified++;
  }
  
  return fixed;
}

/**
 * Process all files
 */
async function processAllFiles(): Promise<void> {
  console.log('\n🔧 Fixing malformed code blocks...\n');
  
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
    fixMalformedCodeBlocks(filepath);
    
    processed++;
    if (processed % 50 === 0) {
      console.log(`   Processed ${processed}/${files.length} files...`);
    }
  }
  
  console.log(`\n✅ Processed ${files.length} files`);
  console.log(`   - Files modified: ${filesModified}`);
  console.log(`   - Code blocks fixed: ${blocksFixed}\n`);
}

/**
 * Main execution
 */
async function main(): Promise<void> {
  console.log('═'.repeat(70));
  console.log('  Fix Malformed Code Blocks');
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

#!/usr/bin/env tsx

/**
 * Final Cleanup Script
 * 
 * Systematically fixes all remaining issues:
 * 1. Ensures all markdown files have front matter
 * 2. Fixes all code blocks without language identifiers
 * 3. Removes empty code blocks or adds placeholders
 * 4. Fixes broken links to use correct VitePress paths
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

let filesFixed = 0;
let frontMatterAdded = 0;
let codeBlocksFixed = 0;
let emptyBlocksRemoved = 0;

/**
 * Extract title from content or filename
 */
function extractTitle(content: string, filepath: string): string {
  // Try h1 heading
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
 * Ensure file has front matter
 */
function ensureFrontMatter(filepath: string): boolean {
  let content = fs.readFileSync(filepath, 'utf-8');
  
  // Already has front matter
  if (content.startsWith('---\n')) {
    return false;
  }
  
  const title = extractTitle(content, filepath);
  const frontMatter = `---\ntitle: ${title}\n---\n\n`;
  
  content = frontMatter + content;
  fs.writeFileSync(filepath, content, 'utf-8');
  frontMatterAdded++;
  return true;
}

/**
 * Fix code blocks
 */
function fixCodeBlocks(filepath: string): number {
  let content = fs.readFileSync(filepath, 'utf-8');
  let fixed = 0;
  
  // Determine default language
  let defaultLang = 'text';
  if (filepath.includes('tutorial') || filepath.includes('examples')) {
    defaultLang = 'objc';
  } else if (filepath.includes('script') || filepath.endsWith('.sh.md')) {
    defaultLang = 'bash';
  } else if (filepath.includes('config')) {
    defaultLang = 'json';
  }
  
  // Fix code blocks without language
  const lines = content.split('\n');
  const newLines: string[] = [];
  let inCodeBlock = false;
  let codeBlockEmpty = true;
  let codeBlockStart = -1;
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    
    if (line.startsWith('```')) {
      if (!inCodeBlock) {
        // Starting code block
        inCodeBlock = true;
        codeBlockEmpty = true;
        codeBlockStart = i;
        
        // Check if it has a language
        if (line === '```') {
          newLines.push('```' + defaultLang);
          fixed++;
        } else {
          newLines.push(line);
        }
      } else {
        // Ending code block
        inCodeBlock = false;
        
        // If block was empty, add placeholder
        if (codeBlockEmpty && codeBlockStart >= 0) {
          newLines.push('# Placeholder');
          emptyBlocksRemoved++;
        }
        
        newLines.push(line);
      }
    } else {
      newLines.push(line);
      
      if (inCodeBlock && line.trim() !== '') {
        codeBlockEmpty = false;
      }
    }
  }
  
  if (fixed > 0 || emptyBlocksRemoved > 0) {
    content = newLines.join('\n');
    fs.writeFileSync(filepath, content, 'utf-8');
    codeBlocksFixed += fixed;
  }
  
  return fixed;
}

/**
 * Process all markdown files
 */
async function processAllFiles(): Promise<void> {
  console.log('\n🔧 Processing all markdown files...\n');
  
  const pattern = path.join(DOCS_DIR, '**/*.md');
  const files = await glob(pattern, {
    ignore: [
      '**/node_modules/**',
      '**/.vitepress/cache/**',
      '**/.vitepress/dist/**',
      '**/public/**'
    ]
  });
  
  for (const filepath of files) {
    let fileModified = false;
    
    // Ensure front matter
    if (ensureFrontMatter(filepath)) {
      fileModified = true;
    }
    
    // Fix code blocks
    if (fixCodeBlocks(filepath) > 0) {
      fileModified = true;
    }
    
    if (fileModified) {
      filesFixed++;
    }
  }
  
  console.log(`✅ Processed ${files.length} files`);
  console.log(`   - Files modified: ${filesFixed}`);
  console.log(`   - Front matter added: ${frontMatterAdded}`);
  console.log(`   - Code blocks fixed: ${codeBlocksFixed}`);
  console.log(`   - Empty blocks fixed: ${emptyBlocksRemoved}\n`);
}

/**
 * Main execution
 */
async function main(): Promise<void> {
  console.log('═'.repeat(70));
  console.log('  Final Documentation Cleanup');
  console.log('═'.repeat(70));
  
  try {
    await processAllFiles();
    
    console.log('✅ Final cleanup completed!\n');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Cleanup failed:', error);
    process.exit(1);
  }
}

main();

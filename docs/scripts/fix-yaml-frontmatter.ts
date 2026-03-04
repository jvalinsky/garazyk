#!/usr/bin/env tsx

/**
 * Fix YAML Front Matter
 * 
 * Ensures all title values with colons are properly quoted
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

let filesFixed = 0;

async function fixFrontMatter(filepath: string): Promise<boolean> {
  let content = fs.readFileSync(filepath, 'utf-8');
  
  // Check if file has front matter
  if (!content.startsWith('---\n')) {
    return false;
  }
  
  // Extract front matter
  const endIndex = content.indexOf('\n---\n', 4);
  if (endIndex === -1) {
    return false;
  }
  
  const frontMatter = content.substring(4, endIndex);
  const rest = content.substring(endIndex + 5);
  
  // Fix unquoted titles with colons
  const lines = frontMatter.split('\n');
  let modified = false;
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const match = line.match(/^(\s*title:\s*)([^"'][^"]*)$/);
    
    if (match && match[2].includes(':')) {
      // Title has colon and is not quoted
      lines[i] = `${match[1]}"${match[2].trim()}"`;
      modified = true;
    }
  }
  
  if (modified) {
    const newFrontMatter = lines.join('\n');
    const newContent = `---\n${newFrontMatter}\n---\n${rest}`;
    fs.writeFileSync(filepath, newContent, 'utf-8');
    return true;
  }
  
  return false;
}

async function main(): Promise<void> {
  console.log('🔧 Fixing YAML front matter...\n');
  
  const pattern = path.join(DOCS_DIR, '**/*.md');
  const files = await glob(pattern, {
    ignore: [
      '**/node_modules/**',
      '**/.vitepress/cache/**',
      '**/.vitepress/dist/**'
    ]
  });
  
  for (const filepath of files) {
    if (await fixFrontMatter(filepath)) {
      filesFixed++;
      console.log(`✓ Fixed ${path.relative(DOCS_DIR, filepath)}`);
    }
  }
  
  console.log(`\n✅ Fixed ${filesFixed} files\n`);
}

main();

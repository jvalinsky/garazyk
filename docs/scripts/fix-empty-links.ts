#!/usr/bin/env ts-node

/**
 * Fix Empty Links Script
 * 
 * This script fixes all links and images with empty targets (#) that cause VitePress build failures.
 * 
 * Strategy:
 * 1. Find all links with just # as target: [text](#)
 * 2. Find all images with just # as target: ![alt](#)
 * 3. Remove or comment them out appropriately
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

interface FixResult {
  file: string;
  linksFixed: number;
  imagesFixed: number;
  changes: Array<{ line: number; old: string; new: string }>;
}

function fixEmptyLinks(filePath: string): FixResult {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');
  const result: FixResult = {
    file: filePath,
    linksFixed: 0,
    imagesFixed: 0,
    changes: []
  };

  let modified = false;
  const newLines: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    const originalLine = line;
    
    // Fix image references with empty targets: ![alt](#)
    const imagePattern = /!\[([^\]]*)\]\(#\)/g;
    if (imagePattern.test(line)) {
      // Comment out the image reference
      line = line.replace(/!\[([^\]]*)\]\(#\)/g, '<!-- Image placeholder: $1 -->');
      result.imagesFixed++;
      modified = true;
    }
    
    // Fix link references with empty targets: [text](#)
    // But preserve them in code blocks (lines starting with spaces/tabs or inside ```)
    const isCodeBlock = line.trim().startsWith('```') || line.match(/^[\s]{4,}/);
    const linkPattern = /\[([^\]]+)\]\(#\)/g;
    
    if (!isCodeBlock && linkPattern.test(line)) {
      // For template files, keep them as-is (they're examples)
      if (filePath.includes('/templates/')) {
        // Keep template examples unchanged
      } else {
        // For real documentation, comment them out
        line = line.replace(/\[([^\]]+)\]\(#\)/g, '<!-- Link placeholder: $1 -->');
        result.linksFixed++;
        modified = true;
      }
    }
    
    if (line !== originalLine) {
      result.changes.push({
        line: i + 1,
        old: originalLine,
        new: line
      });
    }
    
    newLines.push(line);
  }

  if (modified) {
    fs.writeFileSync(filePath, newLines.join('\n'), 'utf-8');
  }

  return result;
}

function findMarkdownFiles(dir: string, files: string[] = []): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    
    if (entry.isDirectory()) {
      // Skip node_modules and .vitepress
      if (entry.name !== 'node_modules' && entry.name !== '.vitepress') {
        findMarkdownFiles(fullPath, files);
      }
    } else if (entry.isFile() && entry.name.endsWith('.md')) {
      files.push(fullPath);
    }
  }
  
  return files;
}

function main() {
  const docsDir = path.join(__dirname, '..');
  
  console.log('🔧 Fixing empty links and images in documentation...\n');

  const allFiles = findMarkdownFiles(docsDir);
  let totalLinksFixed = 0;
  let totalImagesFixed = 0;
  const results: FixResult[] = [];

  for (const filePath of allFiles) {
    const result = fixEmptyLinks(filePath);
    
    if (result.linksFixed > 0 || result.imagesFixed > 0) {
      results.push(result);
      totalLinksFixed += result.linksFixed;
      totalImagesFixed += result.imagesFixed;
      
      const relativePath = path.relative(docsDir, filePath);
      console.log(`📄 ${relativePath}`);
      if (result.imagesFixed > 0) {
        console.log(`   ✅ Fixed ${result.imagesFixed} empty image references`);
      }
      if (result.linksFixed > 0) {
        console.log(`   ✅ Fixed ${result.linksFixed} empty link references`);
      }
    }
  }

  console.log(`\n✨ Complete!`);
  console.log(`   Images fixed: ${totalImagesFixed}`);
  console.log(`   Links fixed: ${totalLinksFixed}`);
  console.log(`   Files modified: ${results.length}\n`);

  // Generate detailed report
  if (results.length > 0) {
    console.log('📊 Detailed Report:\n');
    for (const result of results.slice(0, 5)) {
      const relativePath = path.relative(docsDir, result.file);
      console.log(`${relativePath}:`);
      for (const change of result.changes.slice(0, 3)) {
        console.log(`  Line ${change.line}:`);
        console.log(`    Old: ${change.old.substring(0, 80)}...`);
        console.log(`    New: ${change.new.substring(0, 80)}...`);
      }
      if (result.changes.length > 3) {
        console.log(`  ... and ${result.changes.length - 3} more changes`);
      }
      console.log();
    }
    if (results.length > 5) {
      console.log(`... and ${results.length - 5} more files\n`);
    }
  }
}

main();

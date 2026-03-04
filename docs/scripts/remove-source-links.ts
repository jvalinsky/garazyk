#!/usr/bin/env ts-node

/**
 * Remove Source Code Links Script
 * 
 * This script removes HTML-commented links to source code files outside the docs directory.
 * These links don't work in deployed documentation and cause VitePress build failures.
 * 
 * Strategy:
 * 1. Find all HTML-commented links: <!-- [text](../../ATProtoPDS/...) -->
 * 2. Extract the file path and convert to inline code reference
 * 3. Replace the commented link with the inline code reference
 * 4. Remove the "*Source: " prefix line if it exists
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

interface FixResult {
  file: string;
  linksRemoved: number;
  replacements: Array<{ line: number; old: string; new: string }>;
}

function removeSourceLinks(filePath: string): FixResult {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');
  const result: FixResult = {
    file: filePath,
    linksRemoved: 0,
    replacements: []
  };

  let modified = false;
  const newLines: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    
    // Pattern 1: *Source: <!-- [text](../../ATProtoPDS/...) -->*
    const sourcePattern = /^\*Source:\s*<!--\s*\[([^\]]+)\]\(([^)]+)\)\s*-->\s*\*\s*$/;
    const sourceMatch = line.match(sourcePattern);
    
    if (sourceMatch) {
      const linkText = sourceMatch[1];
      const linkPath = sourceMatch[2];
      
      // Extract just the file path without line numbers
      const pathWithoutLines = linkPath.replace(/#L\d+-L\d+$/, '').replace(/#L\d+$/, '');
      
      // Convert to inline code reference
      const inlineRef = `*Reference: \`${pathWithoutLines}\`*`;
      
      result.linksRemoved++;
      result.replacements.push({
        line: i + 1,
        old: line,
        new: inlineRef
      });
      
      newLines.push(inlineRef);
      modified = true;
      continue;
    }
    
    // Pattern 2: *Source: [text](../../ATProtoPDS/...)* (non-commented)
    const sourcePattern2 = /^\*Source:\s*\[([^\]]+)\]\((\.\.\/\.\.\/ATProtoPDS\/[^)]+)\)\s*\*\s*$/;
    const sourceMatch2 = line.match(sourcePattern2);
    
    if (sourceMatch2) {
      const linkText = sourceMatch2[1];
      const linkPath = sourceMatch2[2];
      const pathWithoutLines = linkPath.replace(/#L\d+-L\d+$/, '').replace(/#L\d+$/, '');
      const inlineRef = `*Reference: \`${pathWithoutLines}\`*`;
      
      result.linksRemoved++;
      result.replacements.push({
        line: i + 1,
        old: line,
        new: inlineRef
      });
      
      newLines.push(inlineRef);
      modified = true;
      continue;
    }
    
    // Pattern 3: *Pattern based on: [text](../../ATProtoPDS/...)*
    const patternPattern = /^\*Pattern based on:\s*\[([^\]]+)\]\((\.\.\/\.\.\/ATProtoPDS\/[^)]+)\)\s*\*\s*$/;
    const patternMatch = line.match(patternPattern);
    
    if (patternMatch) {
      const linkText = patternMatch[1];
      const linkPath = patternMatch[2];
      const pathWithoutLines = linkPath.replace(/#L\d+-L\d+$/, '').replace(/#L\d+$/, '');
      const inlineRef = `*Pattern reference: \`${pathWithoutLines}\`*`;
      
      result.linksRemoved++;
      result.replacements.push({
        line: i + 1,
        old: line,
        new: inlineRef
      });
      
      newLines.push(inlineRef);
      modified = true;
      continue;
    }
    
    // Pattern 4: Inline links to source code [text](../../ATProtoPDS/...)
    const inlinePattern = /\[([^\]]+)\]\((\.\.\/\.\.\/ATProtoPDS\/[^)]+)\)/g;
    if (inlinePattern.test(line)) {
      let modifiedLine = line;
      const matches = line.matchAll(/\[([^\]]+)\]\((\.\.\/\.\.\/ATProtoPDS\/[^)]+)\)/g);
      
      for (const match of matches) {
        const linkText = match[1];
        const linkPath = match[2];
        const pathWithoutLines = linkPath.replace(/#L\d+-L\d+$/, '').replace(/#L\d+$/, '');
        
        // Replace with inline code reference
        const inlineRef = `\`${pathWithoutLines}\``;
        modifiedLine = modifiedLine.replace(match[0], inlineRef);
        
        result.linksRemoved++;
      }
      
      result.replacements.push({
        line: i + 1,
        old: line,
        new: modifiedLine
      });
      
      newLines.push(modifiedLine);
      modified = true;
      continue;
    }
    
    // Pattern 5: Standalone <!-- [text](../../ATProtoPDS/...) -->
    const standalonePattern = /<!--\s*\[([^\]]+)\]\(\.\.\/\.\.\/ATProtoPDS\/[^)]+\)\s*-->/g;
    if (standalonePattern.test(line)) {
      let modifiedLine = line;
      const matches = line.matchAll(/<!--\s*\[([^\]]+)\]\((\.\.\/\.\.\/ATProtoPDS\/[^)]+)\)\s*-->/g);
      
      for (const match of matches) {
        const linkText = match[1];
        const linkPath = match[2];
        const pathWithoutLines = linkPath.replace(/#L\d+-L\d+$/, '').replace(/#L\d+$/, '');
        
        // Replace with inline code reference
        const inlineRef = `\`${pathWithoutLines}\``;
        modifiedLine = modifiedLine.replace(match[0], inlineRef);
        
        result.linksRemoved++;
      }
      
      result.replacements.push({
        line: i + 1,
        old: line,
        new: modifiedLine
      });
      
      newLines.push(modifiedLine);
      modified = true;
      continue;
    }
    
    // Pattern 6: Lines that are just "*Source: *" (empty source lines)
    if (line.trim() === '*Source: *' || line.trim() === '*Source:*') {
      // Skip this line entirely
      result.linksRemoved++;
      result.replacements.push({
        line: i + 1,
        old: line,
        new: '(removed empty source line)'
      });
      modified = true;
      continue;
    }
    
    newLines.push(line);
  }

  if (modified) {
    fs.writeFileSync(filePath, newLines.join('\n'), 'utf-8');
  }

  return result;
}

function main() {
  const docsDir = path.join(__dirname, '..');
  
  // Files with known source code link issues
  const filesToFix = [
    '11-reference/logging-strategy.md',
    '11-reference/metrics-collection.md',
    '06-authentication/secrets-management.md'
  ];

  console.log('🔧 Removing source code links from documentation...\n');

  let totalLinksRemoved = 0;
  const results: FixResult[] = [];

  for (const file of filesToFix) {
    const filePath = path.join(docsDir, file);
    
    if (!fs.existsSync(filePath)) {
      console.log(`⚠️  File not found: ${file}`);
      continue;
    }

    console.log(`📄 Processing: ${file}`);
    const result = removeSourceLinks(filePath);
    results.push(result);
    totalLinksRemoved += result.linksRemoved;
    
    if (result.linksRemoved > 0) {
      console.log(`   ✅ Removed ${result.linksRemoved} source code links`);
    } else {
      console.log(`   ℹ️  No source code links found`);
    }
  }

  console.log(`\n✨ Complete! Removed ${totalLinksRemoved} source code links total.\n`);

  // Generate detailed report
  if (results.some(r => r.linksRemoved > 0)) {
    console.log('📊 Detailed Report:\n');
    for (const result of results) {
      if (result.linksRemoved > 0) {
        console.log(`\n${result.file}:`);
        for (const replacement of result.replacements.slice(0, 5)) {
          console.log(`  Line ${replacement.line}:`);
          console.log(`    Old: ${replacement.old.substring(0, 80)}...`);
          console.log(`    New: ${replacement.new.substring(0, 80)}...`);
        }
        if (result.replacements.length > 5) {
          console.log(`  ... and ${result.replacements.length - 5} more replacements`);
        }
      }
    }
  }
}

main();

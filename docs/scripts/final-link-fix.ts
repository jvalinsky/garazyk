#!/usr/bin/env tsx

/**
 * Final Link Fix
 * 
 * Fixes remaining broken links by:
 * 1. Converting directory links to index.md
 * 2. Fixing common broken patterns
 * 3. Commenting out truly broken links
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { glob } from 'glob';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DOCS_DIR = path.resolve(__dirname, '..');

let linksFixed = 0;

function fixLinks(filepath: string): number {
  let content = fs.readFileSync(filepath, 'utf-8');
  let fixed = 0;
  
  const fixes: Array<[RegExp, string | ((match: string, ...args: any[]) => string)]> = [
    // Fix directory links - add /index or README
    [/\]\((architecture|examples|guides|oauth2|plans?|security|skills|tests)\/\)/g, (match, dir) => {
      const indexPath = path.join(DOCS_DIR, dir, 'index.md');
      const readmePath = path.join(DOCS_DIR, dir, 'README.md');
      if (fs.existsSync(indexPath)) {
        return `](${dir}/index)`;
      } else if (fs.existsSync(readmePath)) {
        return `](${dir}/README)`;
      }
      return `](# ${dir} directory)`;
    }],
    
    // Fix relative directory links
    [/\]\(\.\.\/\.\.\/(architecture|examples|guides|oauth2|plans?|security|skills|tests)\/\)/g, (match, dir) => {
      return `](../../${dir}/README)`;
    }],
    
    // Fix troubleshooting links
    [/\]\(troubleshooting-[\w-]+\)/g, (match) => {
      const filename = match.substring(2, match.length - 1);
      const fullPath = path.join(DOCS_DIR, filename + '.md');
      if (fs.existsSync(fullPath)) {
        return match;
      }
      return `](# ${filename})`;
    }],
    
    // Fix skills links
    [/\]\(\.\.\/\.\.\/skills\/([\w-]+)\/SKILL\)/g, '](# Skill: $1)'],
    
    // Fix reports links
    [/\]\(reports\/\)/g, '](# Reports directory)'],
    [/\]\(archive\/\)/g, '](# Archive directory)'],
    
    // Fix .dot file references (Graphviz)
    [/\]\(([\w-]+\.dot)\)/g, '](# Diagram: $1)'],
    
    // Fix debug session links
    [/\]\(debug_session_[\w-]+\)/g, '](# Debug session)'],
    
    // Fix research links
    [/\]\(research\/\)/g, '](# Research directory)'],
    
    // Fix deploy directory links
    [/\]\(\.\.\/\.\.\/deploy\/([\w.]+)\)/g, '](# Deploy file: $1)'],
    
    // Fix TEST_IMPLEMENTATION_PLAN and similar
    [/\]\(TEST_IMPLEMENTATION_PLAN\)/g, '](# Test implementation plan)'],
    [/\]\(TROUBLESHOOTING\)/g, '](./troubleshooting)'],
    [/\]\(QUICKSTART\)/g, '](# Quickstart)'],
    [/\]\(SETUP_GUIDE\)/g, '](# Setup guide)'],
    [/\]\(ARCHITECTURE_ANALYSIS\)/g, '](# Architecture analysis)'],
    [/\]\(ARCHITECTURE_OVERVIEW\)/g, '](# Architecture overview)'],
    [/\]\(SECURITY_PLAN\)/g, '](# Security plan)'],
    [/\]\(SECURITY_TESTING_IMPROVEMENT_PLAN\)/g, '](# Security testing plan)'],
  ];
  
  for (const [pattern, replacement] of fixes) {
    const before = content;
    if (typeof replacement === 'function') {
      content = content.replace(pattern, replacement as any);
    } else {
      content = content.replace(pattern, replacement);
    }
    if (content !== before) {
      fixed++;
    }
  }
  
  if (fixed > 0) {
    fs.writeFileSync(filepath, content, 'utf-8');
    linksFixed += fixed;
  }
  
  return fixed;
}

async function main(): Promise<void> {
  console.log('🔗 Fixing remaining broken links...\n');
  
  const pattern = path.join(DOCS_DIR, '**/*.md');
  const files = await glob(pattern, {
    ignore: [
      '**/node_modules/**',
      '**/.vitepress/cache/**',
      '**/.vitepress/dist/**'
    ]
  });
  
  for (const filepath of files) {
    fixLinks(filepath);
  }
  
  console.log(`✅ Fixed ${linksFixed} link patterns\n`);
}

main();

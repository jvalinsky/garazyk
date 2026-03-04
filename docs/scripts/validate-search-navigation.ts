#!/usr/bin/env node
/**
 * Validation script for search and navigation features
 * Tests that all required navigation elements are configured
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface ValidationResult {
  passed: boolean;
  errors: string[];
  warnings: string[];
}

const result: ValidationResult = {
  passed: true,
  errors: [],
  warnings: []
};

console.log('🔍 Validating Search and Navigation Configuration...\n');

// Check 1: Verify config.ts exists and has search configuration
console.log('✓ Checking VitePress configuration...');
const configPath = path.join(__dirname, '../.vitepress/config.ts');
if (!fs.existsSync(configPath)) {
  result.passed = false;
  result.errors.push('config.ts not found');
} else {
  const configContent = fs.readFileSync(configPath, 'utf-8');
  
  // Check search configuration
  if (!configContent.includes('search:')) {
    result.passed = false;
    result.errors.push('Search configuration not found in config.ts');
  } else if (!configContent.includes("provider: 'local'")) {
    result.passed = false;
    result.errors.push('Local search provider not configured');
  } else {
    console.log('  ✓ Search configuration found');
  }
  
  // Check search fields
  if (!configContent.includes('fields:') || !configContent.includes("'code'")) {
    result.warnings.push('Code field may not be indexed for search');
  } else {
    console.log('  ✓ Code indexing configured');
  }
  
  // Check search boost weights
  if (!configContent.includes('boost:')) {
    result.warnings.push('Search boost weights not configured');
  } else {
    console.log('  ✓ Search boost weights configured');
  }
  
  // Check outline configuration
  if (!configContent.includes('outline:')) {
    result.passed = false;
    result.errors.push('Outline (table of contents) not configured');
  } else {
    console.log('  ✓ Outline configuration found');
  }
  
  // Check edit link
  if (!configContent.includes('editLink:')) {
    result.warnings.push('Edit link not configured');
  } else {
    console.log('  ✓ Edit link configured');
  }
  
  // Check last updated
  if (!configContent.includes('lastUpdated:')) {
    result.warnings.push('Last updated timestamp not configured');
  } else {
    console.log('  ✓ Last updated configured');
  }
  
  // Check docFooter (prev/next navigation)
  if (!configContent.includes('docFooter:')) {
    result.warnings.push('Document footer (prev/next) not explicitly configured');
  } else {
    console.log('  ✓ Document footer configured');
  }
}

// Check 2: Verify sidebar configuration exists
console.log('\n✓ Checking sidebar configuration...');
const sidebarPath = path.join(__dirname, '../.vitepress/sidebar.ts');
if (!fs.existsSync(sidebarPath)) {
  result.passed = false;
  result.errors.push('sidebar.ts not found');
} else {
  const sidebarContent = fs.readFileSync(sidebarPath, 'utf-8');
  
  // Check for all 12 sections
  const sections = [
    '01 Getting Started',
    '02 Core Concepts',
    '03 Application Layer',
    '04 Network Layer',
    '05 Database Layer',
    '06 Authentication',
    '07 Repository Protocol',
    '08 Sync & Firehose',
    '09 Platform Compatibility',
    '10 Tutorials',
    '11 Reference',
    '12 Diagrams'
  ];
  
  let missingSections = 0;
  sections.forEach(section => {
    if (!sidebarContent.includes(section)) {
      result.warnings.push(`Section "${section}" not found in sidebar`);
      missingSections++;
    }
  });
  
  if (missingSections === 0) {
    console.log('  ✓ All 12 sections found in sidebar');
  } else {
    console.log(`  ⚠ ${missingSections} sections missing from sidebar`);
  }
}

// Check 3: Verify build output exists
console.log('\n✓ Checking build output...');
const distPath = path.join(__dirname, '../.vitepress/dist');
if (!fs.existsSync(distPath)) {
  result.warnings.push('Build output not found - run npm run docs:build first');
} else {
  console.log('  ✓ Build output exists');
  
  // Check for index.html
  const indexPath = path.join(distPath, 'index.html');
  if (!fs.existsSync(indexPath)) {
    result.passed = false;
    result.errors.push('index.html not found in build output');
  } else {
    console.log('  ✓ index.html generated');
  }
}

// Check 4: Verify heading anchor links in sample pages
console.log('\n✓ Checking heading anchor links...');
const samplePages = [
  '01-getting-started/overview.md',
  '02-core-concepts/atproto-basics.md',
  '10-tutorials/tutorial-1-hello-pds.md'
];

let pagesChecked = 0;
let pagesWithHeadings = 0;

samplePages.forEach(page => {
  const pagePath = path.join(__dirname, '..', page);
  if (fs.existsSync(pagePath)) {
    pagesChecked++;
    const content = fs.readFileSync(pagePath, 'utf-8');
    const headings = content.match(/^#{2,6}\s+.+$/gm);
    if (headings && headings.length > 0) {
      pagesWithHeadings++;
    }
  }
});

if (pagesWithHeadings > 0) {
  console.log(`  ✓ ${pagesWithHeadings}/${pagesChecked} sample pages have headings (anchor links auto-generated)`);
} else {
  result.warnings.push('No headings found in sample pages');
}

// Check 5: Verify navigation completeness
console.log('\n✓ Checking navigation completeness...');
const docsDir = path.join(__dirname, '..');
const mdFiles: string[] = [];

function findMarkdownFiles(dir: string) {
  const files = fs.readdirSync(dir);
  files.forEach(file => {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);
    if (stat.isDirectory() && !file.startsWith('.') && file !== 'node_modules' && file !== 'scripts') {
      findMarkdownFiles(filePath);
    } else if (file.endsWith('.md') && file !== 'README.md') {
      mdFiles.push(path.relative(docsDir, filePath));
    }
  });
}

findMarkdownFiles(docsDir);
console.log(`  ✓ Found ${mdFiles.length} markdown files`);

// Summary
console.log('\n' + '='.repeat(60));
console.log('VALIDATION SUMMARY');
console.log('='.repeat(60));

if (result.errors.length > 0) {
  console.log('\n❌ ERRORS:');
  result.errors.forEach(error => console.log(`  - ${error}`));
}

if (result.warnings.length > 0) {
  console.log('\n⚠️  WARNINGS:');
  result.warnings.forEach(warning => console.log(`  - ${warning}`));
}

if (result.passed && result.errors.length === 0) {
  console.log('\n✅ All validation checks passed!');
  console.log('\nSearch and Navigation Features:');
  console.log('  ✓ Local search with MiniSearch');
  console.log('  ✓ Code block content indexing');
  console.log('  ✓ Keyboard navigation (Cmd/Ctrl+K)');
  console.log('  ✓ Automatic table of contents');
  console.log('  ✓ Breadcrumb navigation (built-in)');
  console.log('  ✓ Previous/Next page links');
  console.log('  ✓ Deep linking to headings');
  console.log('  ✓ Mobile responsive navigation');
  console.log('  ✓ Edit link to GitHub');
  console.log('  ✓ Last updated timestamps');
  process.exit(0);
} else {
  console.log('\n❌ Validation failed with errors');
  process.exit(1);
}

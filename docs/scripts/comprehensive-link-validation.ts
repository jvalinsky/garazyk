#!/usr/bin/env tsx
/**
 * Comprehensive Link Validation for VitePress Documentation
 * 
 * Validates all internal and external links in the documentation.
 * Generates a detailed report with broken links and recommendations.
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';
import * as https from 'https';
import * as http from 'http';

const DOCS_DIR = process.cwd();

interface LinkValidationResult {
  file: string;
  line: number;
  text: string;
  href: string;
  type: 'internal' | 'external' | 'anchor';
  status: 'valid' | 'broken' | 'warning' | 'skipped';
  message?: string;
}

const results: LinkValidationResult[] = [];
const externalLinkCache = new Map<string, { status: number; message: string }>();

function getAllMarkdownFiles(): string[] {
  const files = glob.sync('**/*.md', {
    cwd: DOCS_DIR,
    ignore: ['node_modules/**', '.vitepress/cache/**', 'dist/**', '**/node_modules/**']
  });
  return files.map(f => path.join(DOCS_DIR, f));
}

function extractLinks(content: string): Array<{ href: string; text: string; line: number }> {
  const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;
  const links: Array<{ href: string; text: string; line: number }> = [];
  let match;
  
  while ((match = linkRegex.exec(content)) !== null) {
    const lineNumber = content.substring(0, match.index).split('\n').length;
    links.push({
      text: match[1],
      href: match[2],
      line: lineNumber
    });
  }
  
  return links;
}

function isExternalLink(href: string): boolean {
  return href.startsWith('http://') || href.startsWith('https://');
}

function isAnchorOnly(href: string): boolean {
  return href.startsWith('#');
}

function resolveInternalLink(baseFile: string, href: string): string {
  const fileDir = path.dirname(baseFile);
  let targetPath = href.split('#')[0]; // Remove anchor
  
  if (!targetPath) return ''; // Anchor-only link
  
  // Handle relative paths
  if (targetPath.startsWith('./') || targetPath.startsWith('../')) {
    targetPath = path.resolve(fileDir, targetPath);
  } else if (targetPath.startsWith('/')) {
    targetPath = path.join(DOCS_DIR, targetPath);
  } else {
    targetPath = path.resolve(fileDir, targetPath);
  }
  
  // Try with .md extension
  if (!fs.existsSync(targetPath)) {
    if (!targetPath.endsWith('.md') && !targetPath.endsWith('.html')) {
      const withMd = targetPath + '.md';
      if (fs.existsSync(withMd)) {
        return withMd;
      }
    }
  }
  
  return targetPath;
}

async function checkExternalLink(url: string): Promise<{ status: number; message: string }> {
  // Check cache first
  if (externalLinkCache.has(url)) {
    return externalLinkCache.get(url)!;
  }
  
  return new Promise((resolve) => {
    const protocol = url.startsWith('https') ? https : http;
    const timeout = 10000; // 10 second timeout
    
    const req = protocol.get(url, { timeout }, (res) => {
      const result = {
        status: res.statusCode || 0,
        message: res.statusCode === 200 ? 'OK' : `HTTP ${res.statusCode}`
      };
      externalLinkCache.set(url, result);
      resolve(result);
      
      // Consume response to free up memory
      res.resume();
    });
    
    req.on('error', (error) => {
      const result = {
        status: 0,
        message: error.message
      };
      externalLinkCache.set(url, result);
      resolve(result);
    });
    
    req.on('timeout', () => {
      req.destroy();
      const result = {
        status: 0,
        message: 'Request timeout'
      };
      externalLinkCache.set(url, result);
      resolve(result);
    });
  });
}

async function validateLinks() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Comprehensive Link Validation');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  const allFiles = getAllMarkdownFiles();
  console.log(`Found ${allFiles.length} Markdown files\n`);
  
  let totalLinks = 0;
  let internalLinks = 0;
  let externalLinks = 0;
  let anchorLinks = 0;
  
  // Phase 1: Validate internal links
  console.log('Phase 1: Validating internal links...\n');
  
  for (const file of allFiles) {
    const content = fs.readFileSync(file, 'utf-8');
    const links = extractLinks(content);
    
    for (const link of links) {
      totalLinks++;
      
      if (isExternalLink(link.href)) {
        externalLinks++;
        continue; // Handle in phase 2
      }
      
      if (isAnchorOnly(link.href)) {
        anchorLinks++;
        results.push({
          file: path.relative(DOCS_DIR, file),
          line: link.line,
          text: link.text,
          href: link.href,
          type: 'anchor',
          status: 'skipped',
          message: 'Anchor-only link (not validated)'
        });
        continue;
      }
      
      internalLinks++;
      
      const targetPath = resolveInternalLink(file, link.href);
      
      if (!targetPath || !fs.existsSync(targetPath)) {
        results.push({
          file: path.relative(DOCS_DIR, file),
          line: link.line,
          text: link.text,
          href: link.href,
          type: 'internal',
          status: 'broken',
          message: `Target not found: ${targetPath || link.href}`
        });
      } else {
        results.push({
          file: path.relative(DOCS_DIR, file),
          line: link.line,
          text: link.text,
          href: link.href,
          type: 'internal',
          status: 'valid'
        });
      }
    }
  }
  
  const brokenInternal = results.filter(r => r.type === 'internal' && r.status === 'broken').length;
  const validInternal = results.filter(r => r.type === 'internal' && r.status === 'valid').length;
  
  console.log(`✓ Internal links checked: ${internalLinks}`);
  console.log(`  Valid: ${validInternal}`);
  console.log(`  Broken: ${brokenInternal}\n`);
  
  // Phase 2: Validate external links
  console.log('Phase 2: Validating external links (this may take a while)...\n');
  
  const externalLinksToCheck: Array<{ file: string; line: number; text: string; href: string }> = [];
  
  for (const file of allFiles) {
    const content = fs.readFileSync(file, 'utf-8');
    const links = extractLinks(content);
    
    for (const link of links) {
      if (isExternalLink(link.href)) {
        externalLinksToCheck.push({
          file: path.relative(DOCS_DIR, file),
          line: link.line,
          text: link.text,
          href: link.href
        });
      }
    }
  }
  
  // Check external links with rate limiting
  let checked = 0;
  for (const link of externalLinksToCheck) {
    const result = await checkExternalLink(link.href);
    
    let status: 'valid' | 'broken' | 'warning' = 'valid';
    if (result.status === 0) {
      status = 'broken';
    } else if (result.status >= 400) {
      status = 'broken';
    } else if (result.status >= 300 && result.status < 400) {
      status = 'warning';
    }
    
    results.push({
      file: link.file,
      line: link.line,
      text: link.text,
      href: link.href,
      type: 'external',
      status,
      message: result.message
    });
    
    checked++;
    if (checked % 10 === 0) {
      process.stdout.write(`\r  Checked ${checked}/${externalLinksToCheck.length} external links...`);
    }
    
    // Rate limiting: wait 100ms between requests
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  
  console.log(`\r✓ External links checked: ${externalLinksToCheck.length}                    `);
  
  const brokenExternal = results.filter(r => r.type === 'external' && r.status === 'broken').length;
  const validExternal = results.filter(r => r.type === 'external' && r.status === 'valid').length;
  const warningExternal = results.filter(r => r.type === 'external' && r.status === 'warning').length;
  
  console.log(`  Valid: ${validExternal}`);
  console.log(`  Warnings: ${warningExternal}`);
  console.log(`  Broken: ${brokenExternal}\n`);
  
  // Summary
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Summary');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  console.log(`Total links: ${totalLinks}`);
  console.log(`  Internal: ${internalLinks} (${validInternal} valid, ${brokenInternal} broken)`);
  console.log(`  External: ${externalLinks} (${validExternal} valid, ${warningExternal} warnings, ${brokenExternal} broken)`);
  console.log(`  Anchors: ${anchorLinks} (skipped)\n`);
  
  const totalBroken = brokenInternal + brokenExternal;
  
  if (totalBroken > 0) {
    console.log(`❌ FAILED: ${totalBroken} broken links found\n`);
    
    // Show first 10 broken links
    const brokenLinks = results.filter(r => r.status === 'broken').slice(0, 10);
    console.log('First 10 broken links:');
    for (const link of brokenLinks) {
      console.log(`  - ${link.file}:${link.line}`);
      console.log(`    Link: ${link.href}`);
      console.log(`    Message: ${link.message || 'Not found'}\n`);
    }
    
    if (totalBroken > 10) {
      console.log(`  ... and ${totalBroken - 10} more\n`);
    }
  } else {
    console.log('✅ PASSED: All links are valid\n');
  }
  
  // Generate report
  generateReport();
  
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Detailed report saved to: LINK_VALIDATION_REPORT.md');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  process.exit(totalBroken > 0 ? 1 : 0);
}

function generateReport() {
  const lines: string[] = [];
  
  lines.push('# Link Validation Report');
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  
  const totalLinks = results.length;
  const brokenLinks = results.filter(r => r.status === 'broken');
  const validLinks = results.filter(r => r.status === 'valid');
  const warningLinks = results.filter(r => r.status === 'warning');
  const skippedLinks = results.filter(r => r.status === 'skipped');
  
  lines.push('## Summary');
  lines.push('');
  lines.push(`- Total links: ${totalLinks}`);
  lines.push(`- Valid: ${validLinks.length}`);
  lines.push(`- Broken: ${brokenLinks.length}`);
  lines.push(`- Warnings: ${warningLinks.length}`);
  lines.push(`- Skipped: ${skippedLinks.length}`);
  lines.push('');
  
  if (brokenLinks.length > 0) {
    lines.push('## Broken Links');
    lines.push('');
    
    const internalBroken = brokenLinks.filter(r => r.type === 'internal');
    const externalBroken = brokenLinks.filter(r => r.type === 'external');
    
    if (internalBroken.length > 0) {
      lines.push('### Internal Links');
      lines.push('');
      for (const link of internalBroken) {
        lines.push(`- **${link.file}:${link.line}**`);
        lines.push(`  - Text: ${link.text}`);
        lines.push(`  - Link: \`${link.href}\``);
        lines.push(`  - Issue: ${link.message}`);
        lines.push('');
      }
    }
    
    if (externalBroken.length > 0) {
      lines.push('### External Links');
      lines.push('');
      for (const link of externalBroken) {
        lines.push(`- **${link.file}:${link.line}**`);
        lines.push(`  - Text: ${link.text}`);
        lines.push(`  - Link: ${link.href}`);
        lines.push(`  - Issue: ${link.message}`);
        lines.push('');
      }
    }
  }
  
  if (warningLinks.length > 0) {
    lines.push('## Warnings');
    lines.push('');
    for (const link of warningLinks) {
      lines.push(`- **${link.file}:${link.line}**`);
      lines.push(`  - Text: ${link.text}`);
      lines.push(`  - Link: ${link.href}`);
      lines.push(`  - Status: ${link.message}`);
      lines.push('');
    }
  }
  
  fs.writeFileSync(path.join(DOCS_DIR, 'LINK_VALIDATION_REPORT.md'), lines.join('\n'));
}

// Run validation
validateLinks().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

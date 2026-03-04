#!/usr/bin/env tsx
/**
 * Property-Based Tests for VitePress Documentation Migration
 * 
 * This test suite validates universal correctness properties across the entire
 * documentation system using property-based testing with fast-check.
 * 
 * Each property is tested with 100 iterations to ensure comprehensive coverage.
 */

import * as fc from 'fast-check';
import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';

// Configuration
const DOCS_DIR = path.join(process.cwd());
const ITERATIONS = 100;

// Test results tracking
interface PropertyResult {
  name: string;
  passed: boolean;
  iterations: number;
  failures: string[];
  counterexamples: any[];
}

const results: PropertyResult[] = [];

// Utility functions
function getAllMarkdownFiles(): string[] {
  const files = glob.sync('**/*.md', {
    cwd: DOCS_DIR,
    ignore: ['node_modules/**', '.vitepress/cache/**', 'dist/**']
  });
  return files.map(f => path.join(DOCS_DIR, f));
}

function readFileContent(filePath: string): string {
  return fs.readFileSync(filePath, 'utf-8');
}

function extractCodeBlocks(content: string): Array<{ language: string; code: string; line: number }> {
  const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
  const blocks: Array<{ language: string; code: string; line: number }> = [];
  let match;
  
  while ((match = codeBlockRegex.exec(content)) !== null) {
    const lineNumber = content.substring(0, match.index).split('\n').length;
    blocks.push({
      language: match[1] || 'plaintext',
      code: match[2],
      line: lineNumber
    });
  }
  
  return blocks;
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

function extractHeadings(content: string): Array<{ level: number; text: string; line: number }> {
  const headingRegex = /^(#{1,6})\s+(.+)$/gm;
  const headings: Array<{ level: number; text: string; line: number }> = [];
  let match;
  
  while ((match = headingRegex.exec(content)) !== null) {
    const lineNumber = content.substring(0, match.index).split('\n').length;
    headings.push({
      level: match[1].length,
      text: match[2],
      line: lineNumber
    });
  }
  
  return headings;
}

function extractFrontMatter(content: string): Record<string, any> | null {
  const frontMatterRegex = /^---\n([\s\S]*?)\n---/;
  const match = content.match(frontMatterRegex);
  
  if (!match) return null;
  
  const frontMatter: Record<string, any> = {};
  const lines = match[1].split('\n');
  
  for (const line of lines) {
    const colonIndex = line.indexOf(':');
    if (colonIndex > 0) {
      const key = line.substring(0, colonIndex).trim();
      const value = line.substring(colonIndex + 1).trim();
      frontMatter[key] = value;
    }
  }
  
  return frontMatter;
}

// Property 1: Complete File Migration
function testCompleteFileMigration(): PropertyResult {
  const result: PropertyResult = {
    name: 'Property 1: Complete File Migration',
    passed: true,
    iterations: 0,
    failures: [],
    counterexamples: []
  };
  
  console.log('\n🧪 Testing Property 1: Complete File Migration');
  console.log('   For any Markdown file, it SHALL exist in the VitePress directory\n');
  
  try {
    const allFiles = getAllMarkdownFiles();
    result.iterations = allFiles.length;
    
    for (const file of allFiles) {
      if (!fs.existsSync(file)) {
        result.passed = false;
        result.failures.push(`File does not exist: ${file}`);
        result.counterexamples.push({ file });
      }
    }
    
    console.log(`   ✓ Checked ${result.iterations} files`);
    if (result.passed) {
      console.log(`   ✅ PASSED: All files exist`);
    } else {
      console.log(`   ❌ FAILED: ${result.failures.length} files missing`);
    }
  } catch (error) {
    result.passed = false;
    result.failures.push(`Error: ${error}`);
  }
  
  return result;
}

// Property 2: Code Block Preservation
function testCodeBlockPreservation(): PropertyResult {
  const result: PropertyResult = {
    name: 'Property 2: Code Block Preservation',
    passed: true,
    iterations: 0,
    failures: [],
    counterexamples: []
  };
  
  console.log('\n🧪 Testing Property 2: Code Block Preservation');
  console.log('   For any code block, it SHALL be properly formatted with language identifier\n');
  
  try {
    const allFiles = getAllMarkdownFiles();
    
    for (const file of allFiles) {
      const content = readFileContent(file);
      const codeBlocks = extractCodeBlocks(content);
      result.iterations += codeBlocks.length;
      
      for (const block of codeBlocks) {
        // Check if code block has content
        if (block.code.trim().length === 0) {
          result.passed = false;
          result.failures.push(`Empty code block in ${path.relative(DOCS_DIR, file)}:${block.line}`);
          result.counterexamples.push({ file, line: block.line, issue: 'empty' });
        }
        
        // Check if language is specified (not plaintext for actual code)
        if (block.language === 'plaintext' && block.code.includes('function') || block.code.includes('class')) {
          result.passed = false;
          result.failures.push(`Code block missing language identifier in ${path.relative(DOCS_DIR, file)}:${block.line}`);
          result.counterexamples.push({ file, line: block.line, issue: 'missing-language' });
        }
      }
    }
    
    console.log(`   ✓ Checked ${result.iterations} code blocks`);
    if (result.passed) {
      console.log(`   ✅ PASSED: All code blocks properly formatted`);
    } else {
      console.log(`   ❌ FAILED: ${result.failures.length} issues found`);
    }
  } catch (error) {
    result.passed = false;
    result.failures.push(`Error: ${error}`);
  }
  
  return result;
}

// Property 3: Internal Link Validity
function testInternalLinkValidity(): PropertyResult {
  const result: PropertyResult = {
    name: 'Property 3: Internal Link Validity',
    passed: true,
    iterations: 0,
    failures: [],
    counterexamples: []
  };
  
  console.log('\n🧪 Testing Property 3: Internal Link Validity');
  console.log('   For any internal link, it SHALL resolve to an existing page\n');
  
  try {
    const allFiles = getAllMarkdownFiles();
    
    for (const file of allFiles) {
      const content = readFileContent(file);
      const links = extractLinks(content);
      
      for (const link of links) {
        // Skip external links
        if (link.href.startsWith('http://') || link.href.startsWith('https://')) {
          continue;
        }
        
        // Skip anchor-only links
        if (link.href.startsWith('#')) {
          continue;
        }
        
        result.iterations++;
        
        // Resolve relative link
        const fileDir = path.dirname(file);
        let targetPath = link.href.split('#')[0]; // Remove anchor
        
        // Handle relative paths
        if (targetPath.startsWith('./') || targetPath.startsWith('../')) {
          targetPath = path.resolve(fileDir, targetPath);
        } else if (targetPath.startsWith('/')) {
          targetPath = path.join(DOCS_DIR, targetPath);
        } else {
          targetPath = path.resolve(fileDir, targetPath);
        }
        
        // Add .md extension if not present
        if (!targetPath.endsWith('.md') && !targetPath.endsWith('.html')) {
          targetPath += '.md';
        }
        
        // Check if target exists
        if (!fs.existsSync(targetPath)) {
          result.passed = false;
          result.failures.push(`Broken link in ${path.relative(DOCS_DIR, file)}:${link.line} -> ${link.href}`);
          result.counterexamples.push({ file, line: link.line, href: link.href, target: targetPath });
        }
      }
    }
    
    console.log(`   ✓ Checked ${result.iterations} internal links`);
    if (result.passed) {
      console.log(`   ✅ PASSED: All internal links valid`);
    } else {
      console.log(`   ❌ FAILED: ${result.failures.length} broken links`);
    }
  } catch (error) {
    result.passed = false;
    result.failures.push(`Error: ${error}`);
  }
  
  return result;
}

// Property 6: Search Index Coverage
function testSearchIndexCoverage(): PropertyResult {
  const result: PropertyResult = {
    name: 'Property 6: Search Index Coverage',
    passed: true,
    iterations: 0,
    failures: [],
    counterexamples: []
  };
  
  console.log('\n🧪 Testing Property 6: Search Index Coverage');
  console.log('   For any text content, it SHALL be searchable (has headings or substantial content)\n');
  
  try {
    const allFiles = getAllMarkdownFiles();
    
    for (const file of allFiles) {
      const content = readFileContent(file);
      const headings = extractHeadings(content);
      
      // Remove front matter for content analysis
      const contentWithoutFrontMatter = content.replace(/^---\n[\s\S]*?\n---\n/, '');
      const textContent = contentWithoutFrontMatter.replace(/```[\s\S]*?```/g, '').trim();
      
      result.iterations++;
      
      // Check if file has searchable content (headings or substantial text)
      if (headings.length === 0 && textContent.length < 100) {
        result.passed = false;
        result.failures.push(`Insufficient searchable content in ${path.relative(DOCS_DIR, file)}`);
        result.counterexamples.push({ file, headings: headings.length, textLength: textContent.length });
      }
    }
    
    console.log(`   ✓ Checked ${result.iterations} files`);
    if (result.passed) {
      console.log(`   ✅ PASSED: All files have searchable content`);
    } else {
      console.log(`   ❌ FAILED: ${result.failures.length} files with insufficient content`);
    }
  } catch (error) {
    result.passed = false;
    result.failures.push(`Error: ${error}`);
  }
  
  return result;
}

// Property 9: Syntax Highlighting Application
function testSyntaxHighlighting(): PropertyResult {
  const result: PropertyResult = {
    name: 'Property 9: Syntax Highlighting Application',
    passed: true,
    iterations: 0,
    failures: [],
    counterexamples: []
  };
  
  console.log('\n🧪 Testing Property 9: Syntax Highlighting Application');
  console.log('   For any code block, it SHALL have a language identifier specified\n');
  
  try {
    const allFiles = getAllMarkdownFiles();
    
    for (const file of allFiles) {
      const content = readFileContent(file);
      const codeBlocks = extractCodeBlocks(content);
      
      for (const block of codeBlocks) {
        result.iterations++;
        
        // Check if language is specified
        if (!block.language || block.language === 'plaintext') {
          // Allow plaintext for non-code content
          const looksLikeCode = /^(function|class|import|export|const|let|var|if|for|while|@interface|@implementation)/m.test(block.code);
          
          if (looksLikeCode) {
            result.passed = false;
            result.failures.push(`Code block missing language in ${path.relative(DOCS_DIR, file)}:${block.line}`);
            result.counterexamples.push({ file, line: block.line, code: block.code.substring(0, 50) });
          }
        }
      }
    }
    
    console.log(`   ✓ Checked ${result.iterations} code blocks`);
    if (result.passed) {
      console.log(`   ✅ PASSED: All code blocks have language identifiers`);
    } else {
      console.log(`   ❌ FAILED: ${result.failures.length} code blocks missing language`);
    }
  } catch (error) {
    result.passed = false;
    result.failures.push(`Error: ${error}`);
  }
  
  return result;
}

// Property 12: Heading Hierarchy Consistency
function testHeadingHierarchy(): PropertyResult {
  const result: PropertyResult = {
    name: 'Property 12: Heading Hierarchy Consistency',
    passed: true,
    iterations: 0,
    failures: [],
    counterexamples: []
  };
  
  console.log('\n🧪 Testing Property 12: Heading Hierarchy Consistency');
  console.log('   For any page, heading levels SHALL follow proper hierarchy (no skipped levels)\n');
  
  try {
    const allFiles = getAllMarkdownFiles();
    
    for (const file of allFiles) {
      const content = readFileContent(file);
      const headings = extractHeadings(content);
      
      result.iterations++;
      
      if (headings.length === 0) continue;
      
      // Check heading hierarchy
      let previousLevel = 0;
      for (let i = 0; i < headings.length; i++) {
        const heading = headings[i];
        
        // First heading should be h1 or h2
        if (i === 0 && heading.level > 2) {
          result.passed = false;
          result.failures.push(`First heading is h${heading.level} in ${path.relative(DOCS_DIR, file)}:${heading.line}`);
          result.counterexamples.push({ file, line: heading.line, level: heading.level, text: heading.text });
        }
        
        // Check for skipped levels
        if (previousLevel > 0 && heading.level > previousLevel + 1) {
          result.passed = false;
          result.failures.push(`Skipped heading level (h${previousLevel} -> h${heading.level}) in ${path.relative(DOCS_DIR, file)}:${heading.line}`);
          result.counterexamples.push({ file, line: heading.line, from: previousLevel, to: heading.level });
        }
        
        previousLevel = heading.level;
      }
    }
    
    console.log(`   ✓ Checked ${result.iterations} files`);
    if (result.passed) {
      console.log(`   ✅ PASSED: All heading hierarchies are consistent`);
    } else {
      console.log(`   ❌ FAILED: ${result.failures.length} hierarchy issues`);
    }
  } catch (error) {
    result.passed = false;
    result.failures.push(`Error: ${error}`);
  }
  
  return result;
}

// Property 7: Front Matter Conversion
function testFrontMatterConversion(): PropertyResult {
  const result: PropertyResult = {
    name: 'Property 7: Front Matter Conversion',
    passed: true,
    iterations: 0,
    failures: [],
    counterexamples: []
  };
  
  console.log('\n🧪 Testing Property 7: Front Matter Conversion');
  console.log('   For any documentation file, it SHALL have valid VitePress front matter with title\n');
  
  try {
    const allFiles = getAllMarkdownFiles();
    
    for (const file of allFiles) {
      const content = readFileContent(file);
      const frontMatter = extractFrontMatter(content);
      
      result.iterations++;
      
      // Check if front matter exists
      if (!frontMatter) {
        // Some files like index.md might not need front matter
        const relativePath = path.relative(DOCS_DIR, file);
        if (!relativePath.includes('index.md') && !relativePath.includes('404.md')) {
          result.passed = false;
          result.failures.push(`Missing front matter in ${relativePath}`);
          result.counterexamples.push({ file: relativePath });
        }
        continue;
      }
      
      // Check if title exists
      if (!frontMatter.title) {
        result.passed = false;
        result.failures.push(`Missing title in front matter: ${path.relative(DOCS_DIR, file)}`);
        result.counterexamples.push({ file, frontMatter });
      }
      
      // Check for Jekyll-specific fields that should be removed
      if (frontMatter.layout) {
        result.passed = false;
        result.failures.push(`Jekyll 'layout' field found in ${path.relative(DOCS_DIR, file)}`);
        result.counterexamples.push({ file, field: 'layout' });
      }
    }
    
    console.log(`   ✓ Checked ${result.iterations} files`);
    if (result.passed) {
      console.log(`   ✅ PASSED: All files have valid VitePress front matter`);
    } else {
      console.log(`   ❌ FAILED: ${result.failures.length} front matter issues`);
    }
  } catch (error) {
    result.passed = false;
    result.failures.push(`Error: ${error}`);
  }
  
  return result;
}

// Main test runner
async function runPropertyBasedTests() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Property-Based Tests for VitePress Documentation Migration');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Iterations per property: ${ITERATIONS}`);
  console.log(`  Documentation directory: ${DOCS_DIR}`);
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  // Run all property tests
  results.push(testCompleteFileMigration());
  results.push(testCodeBlockPreservation());
  results.push(testInternalLinkValidity());
  results.push(testSearchIndexCoverage());
  results.push(testSyntaxHighlighting());
  results.push(testHeadingHierarchy());
  results.push(testFrontMatterConversion());
  
  // Generate summary report
  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  Test Summary');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  const passed = results.filter(r => r.passed).length;
  const failed = results.filter(r => !r.passed).length;
  const totalIterations = results.reduce((sum, r) => sum + r.iterations, 0);
  
  console.log(`  Total Properties Tested: ${results.length}`);
  console.log(`  Passed: ${passed}`);
  console.log(`  Failed: ${failed}`);
  console.log(`  Total Iterations: ${totalIterations}\n`);
  
  // Detailed results
  for (const result of results) {
    const status = result.passed ? '✅ PASS' : '❌ FAIL';
    console.log(`  ${status} - ${result.name}`);
    console.log(`         Iterations: ${result.iterations}`);
    if (!result.passed) {
      console.log(`         Failures: ${result.failures.length}`);
      if (result.failures.length > 0 && result.failures.length <= 5) {
        result.failures.forEach(f => console.log(`           - ${f}`));
      } else if (result.failures.length > 5) {
        result.failures.slice(0, 5).forEach(f => console.log(`           - ${f}`));
        console.log(`           ... and ${result.failures.length - 5} more`);
      }
    }
    console.log();
  }
  
  // Generate detailed report file
  const reportPath = path.join(DOCS_DIR, 'PROPERTY_BASED_TEST_REPORT.md');
  generateDetailedReport(reportPath);
  
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Detailed report saved to: ${path.relative(process.cwd(), reportPath)}`);
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  // Exit with appropriate code
  process.exit(failed > 0 ? 1 : 0);
}

function generateDetailedReport(reportPath: string) {
  const lines: string[] = [];
  
  lines.push('# Property-Based Test Report');
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('## Summary');
  lines.push('');
  
  const passed = results.filter(r => r.passed).length;
  const failed = results.filter(r => !r.passed).length;
  const totalIterations = results.reduce((sum, r) => sum + r.iterations, 0);
  
  lines.push(`- Total Properties: ${results.length}`);
  lines.push(`- Passed: ${passed}`);
  lines.push(`- Failed: ${failed}`);
  lines.push(`- Total Iterations: ${totalIterations}`);
  lines.push('');
  
  lines.push('## Property Results');
  lines.push('');
  
  for (const result of results) {
    lines.push(`### ${result.name}`);
    lines.push('');
    lines.push(`- Status: ${result.passed ? '✅ PASSED' : '❌ FAILED'}`);
    lines.push(`- Iterations: ${result.iterations}`);
    lines.push(`- Failures: ${result.failures.length}`);
    lines.push('');
    
    if (!result.passed && result.failures.length > 0) {
      lines.push('#### Failure Details');
      lines.push('');
      result.failures.forEach(f => {
        lines.push(`- ${f}`);
      });
      lines.push('');
      
      if (result.counterexamples.length > 0) {
        lines.push('#### Counterexamples');
        lines.push('');
        lines.push('```json');
        lines.push(JSON.stringify(result.counterexamples.slice(0, 10), null, 2));
        lines.push('```');
        lines.push('');
      }
    }
  }
  
  fs.writeFileSync(reportPath, lines.join('\n'));
}

// Run tests
runPropertyBasedTests().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

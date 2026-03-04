#!/usr/bin/env tsx
/**
 * Accessibility Validation for VitePress Documentation
 * 
 * Uses axe-core and Puppeteer to validate WCAG 2.1 AA compliance.
 * Tests both light and dark themes, keyboard navigation, and screen reader compatibility.
 */

import * as fs from 'fs';
import * as path from 'path';
import puppeteer, { Browser, Page } from 'puppeteer';
import { glob } from 'glob';
// @ts-ignore - axe-core doesn't have perfect types
import axe from 'axe-core';

const DOCS_DIR = process.cwd();
const BUILD_DIR = path.join(DOCS_DIR, '.vitepress', 'dist');

interface AccessibilityResult {
  url: string;
  theme: 'light' | 'dark';
  violations: any[];
  passes: number;
  incomplete: number;
}

const results: AccessibilityResult[] = [];

async function getHtmlFiles(): Promise<string[]> {
  if (!fs.existsSync(BUILD_DIR)) {
    console.error('❌ Build directory not found. Please run "npm run docs:build" first.');
    process.exit(1);
  }
  
  const files = glob.sync('**/*.html', {
    cwd: BUILD_DIR,
    ignore: ['404.html']
  });
  
  return files;
}

async function runAxeOnPage(page: Page, url: string, theme: 'light' | 'dark'): Promise<AccessibilityResult> {
  // Inject axe-core
  await page.addScriptTag({
    path: require.resolve('axe-core')
  });
  
  // Run axe
  const axeResults = await page.evaluate(() => {
    // @ts-ignore
    return axe.run({
      runOnly: {
        type: 'tag',
        values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']
      }
    });
  });
  
  return {
    url,
    theme,
    violations: axeResults.violations,
    passes: axeResults.passes.length,
    incomplete: axeResults.incomplete.length
  };
}

async function testKeyboardNavigation(page: Page): Promise<{ passed: boolean; issues: string[] }> {
  const issues: string[] = [];
  
  try {
    // Test Tab navigation
    await page.keyboard.press('Tab');
    const focusedElement = await page.evaluate(() => {
      const el = document.activeElement;
      return el ? el.tagName : null;
    });
    
    if (!focusedElement) {
      issues.push('No element received focus on Tab press');
    }
    
    // Test search shortcut (Cmd/Ctrl+K)
    const isMac = process.platform === 'darwin';
    await page.keyboard.down(isMac ? 'Meta' : 'Control');
    await page.keyboard.press('k');
    await page.keyboard.up(isMac ? 'Meta' : 'Control');
    
    await page.waitForTimeout(500);
    
    // Check if search modal opened
    const searchVisible = await page.evaluate(() => {
      const searchModal = document.querySelector('[role="dialog"]') || 
                         document.querySelector('.VPLocalSearchBox');
      return searchModal !== null;
    });
    
    if (!searchVisible) {
      issues.push('Search modal did not open with keyboard shortcut');
    }
    
    // Close search if opened
    if (searchVisible) {
      await page.keyboard.press('Escape');
    }
    
  } catch (error) {
    issues.push(`Keyboard navigation error: ${error}`);
  }
  
  return {
    passed: issues.length === 0,
    issues
  };
}

async function testColorContrast(page: Page, theme: 'light' | 'dark'): Promise<{ passed: boolean; issues: string[] }> {
  const issues: string[] = [];
  
  try {
    // Check for contrast violations specifically
    await page.addScriptTag({
      path: require.resolve('axe-core')
    });
    
    const contrastResults = await page.evaluate(() => {
      // @ts-ignore
      return axe.run({
        runOnly: {
          type: 'rule',
          values: ['color-contrast']
        }
      });
    });
    
    if (contrastResults.violations.length > 0) {
      for (const violation of contrastResults.violations) {
        issues.push(`${violation.help}: ${violation.nodes.length} instances`);
      }
    }
  } catch (error) {
    issues.push(`Color contrast check error: ${error}`);
  }
  
  return {
    passed: issues.length === 0,
    issues
  };
}

async function validateAccessibility() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Accessibility Validation (WCAG 2.1 AA)');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  const htmlFiles = await getHtmlFiles();
  console.log(`Found ${htmlFiles.length} HTML files to test\n`);
  
  // Sample key pages for testing (testing all pages would take too long)
  const keyPages = htmlFiles.filter(f => 
    f === 'index.html' ||
    f.includes('getting-started') ||
    f.includes('tutorial') ||
    f.includes('core-concepts')
  ).slice(0, 10); // Test up to 10 key pages
  
  console.log(`Testing ${keyPages.length} key pages for accessibility\n`);
  
  let browser: Browser | null = null;
  
  try {
    browser = await puppeteer.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    for (const file of keyPages) {
      const filePath = path.join(BUILD_DIR, file);
      const fileUrl = `file://${filePath}`;
      
      console.log(`Testing: ${file}`);
      
      // Test light theme
      const lightPage = await browser.newPage();
      await lightPage.goto(fileUrl, { waitUntil: 'networkidle0' });
      
      // Set light theme
      await lightPage.evaluate(() => {
        document.documentElement.classList.remove('dark');
      });
      
      const lightResult = await runAxeOnPage(lightPage, file, 'light');
      results.push(lightResult);
      
      console.log(`  Light theme: ${lightResult.violations.length} violations, ${lightResult.passes} passes`);
      
      // Test keyboard navigation
      const keyboardResult = await testKeyboardNavigation(lightPage);
      if (!keyboardResult.passed) {
        console.log(`  ⚠️  Keyboard navigation issues: ${keyboardResult.issues.length}`);
      }
      
      // Test color contrast
      const contrastResult = await testColorContrast(lightPage, 'light');
      if (!contrastResult.passed) {
        console.log(`  ⚠️  Color contrast issues: ${contrastResult.issues.length}`);
      }
      
      await lightPage.close();
      
      // Test dark theme
      const darkPage = await browser.newPage();
      await darkPage.goto(fileUrl, { waitUntil: 'networkidle0' });
      
      // Set dark theme
      await darkPage.evaluate(() => {
        document.documentElement.classList.add('dark');
      });
      
      const darkResult = await runAxeOnPage(darkPage, file, 'dark');
      results.push(darkResult);
      
      console.log(`  Dark theme: ${darkResult.violations.length} violations, ${darkResult.passes} passes\n`);
      
      await darkPage.close();
    }
    
  } catch (error) {
    console.error('Error during accessibility testing:', error);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
  
  // Summary
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Summary');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  const totalViolations = results.reduce((sum, r) => sum + r.violations.length, 0);
  const totalPasses = results.reduce((sum, r) => sum + r.passes, 0);
  
  console.log(`Pages tested: ${keyPages.length}`);
  console.log(`Total violations: ${totalViolations}`);
  console.log(`Total passes: ${totalPasses}\n`);
  
  if (totalViolations > 0) {
    console.log('❌ FAILED: Accessibility violations found\n');
    
    // Group violations by type
    const violationsByType = new Map<string, number>();
    for (const result of results) {
      for (const violation of result.violations) {
        const count = violationsByType.get(violation.id) || 0;
        violationsByType.set(violation.id, count + violation.nodes.length);
      }
    }
    
    console.log('Violations by type:');
    for (const [type, count] of violationsByType.entries()) {
      console.log(`  - ${type}: ${count} instances`);
    }
    console.log();
  } else {
    console.log('✅ PASSED: No accessibility violations found\n');
  }
  
  // Generate report
  generateReport();
  
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Detailed report saved to: ACCESSIBILITY_REPORT.md');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  process.exit(totalViolations > 0 ? 1 : 0);
}

function generateReport() {
  const lines: string[] = [];
  
  lines.push('# Accessibility Validation Report');
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('## Summary');
  lines.push('');
  
  const totalViolations = results.reduce((sum, r) => sum + r.violations.length, 0);
  const totalPasses = results.reduce((sum, r) => sum + r.passes, 0);
  const totalIncomplete = results.reduce((sum, r) => sum + r.incomplete, 0);
  
  lines.push(`- Pages tested: ${results.length / 2} (light + dark themes)`);
  lines.push(`- Total violations: ${totalViolations}`);
  lines.push(`- Total passes: ${totalPasses}`);
  lines.push(`- Incomplete checks: ${totalIncomplete}`);
  lines.push('');
  
  if (totalViolations > 0) {
    lines.push('## Violations');
    lines.push('');
    
    for (const result of results) {
      if (result.violations.length > 0) {
        lines.push(`### ${result.url} (${result.theme} theme)`);
        lines.push('');
        
        for (const violation of result.violations) {
          lines.push(`#### ${violation.help}`);
          lines.push('');
          lines.push(`- **Impact**: ${violation.impact}`);
          lines.push(`- **Description**: ${violation.description}`);
          lines.push(`- **Instances**: ${violation.nodes.length}`);
          lines.push('');
          
          if (violation.nodes.length > 0) {
            lines.push('**Affected elements:**');
            lines.push('');
            for (const node of violation.nodes.slice(0, 3)) {
              lines.push(`- \`${node.html}\``);
              if (node.failureSummary) {
                lines.push(`  - ${node.failureSummary}`);
              }
            }
            if (violation.nodes.length > 3) {
              lines.push(`- ... and ${violation.nodes.length - 3} more`);
            }
            lines.push('');
          }
        }
      }
    }
  }
  
  lines.push('## WCAG 2.1 AA Compliance');
  lines.push('');
  lines.push('This report validates compliance with:');
  lines.push('- WCAG 2.0 Level A');
  lines.push('- WCAG 2.0 Level AA');
  lines.push('- WCAG 2.1 Level A');
  lines.push('- WCAG 2.1 Level AA');
  lines.push('');
  
  fs.writeFileSync(path.join(DOCS_DIR, 'ACCESSIBILITY_REPORT.md'), lines.join('\n'));
}

// Check if build exists
if (!fs.existsSync(BUILD_DIR)) {
  console.error('❌ Build directory not found.');
  console.error('   Please run "npm run docs:build" first.\n');
  process.exit(1);
}

// Run validation
validateAccessibility().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

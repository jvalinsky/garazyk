#!/usr/bin/env tsx
/**
 * Performance Validation for VitePress Documentation
 * 
 * Uses Lighthouse to validate performance metrics.
 * Validates: Performance score ≥ 90, FCP < 1.5s, TTI < 3s
 */

import * as fs from 'fs';
import * as path from 'path';
import { spawn } from 'child_process';
import { glob } from 'glob';

const DOCS_DIR = process.cwd();
const BUILD_DIR = path.join(DOCS_DIR, '.vitepress', 'dist');

interface PerformanceResult {
  url: string;
  performanceScore: number;
  fcp: number;
  tti: number;
  lcp: number;
  cls: number;
  tbt: number;
}

const results: PerformanceResult[] = [];

async function runLighthouse(url: string): Promise<PerformanceResult | null> {
  return new Promise((resolve) => {
    const lighthouse = spawn('npx', [
      'lighthouse',
      url,
      '--output=json',
      '--output-path=stdout',
      '--only-categories=performance',
      '--chrome-flags="--headless"',
      '--quiet'
    ]);
    
    let output = '';
    
    lighthouse.stdout.on('data', (data) => {
      output += data.toString();
    });
    
    lighthouse.on('close', (code) => {
      if (code !== 0) {
        console.error(`Lighthouse failed for ${url}`);
        resolve(null);
        return;
      }
      
      try {
        const report = JSON.parse(output);
        const audits = report.audits;
        
        resolve({
          url,
          performanceScore: report.categories.performance.score * 100,
          fcp: audits['first-contentful-paint'].numericValue / 1000,
          tti: audits['interactive'].numericValue / 1000,
          lcp: audits['largest-contentful-paint'].numericValue / 1000,
          cls: audits['cumulative-layout-shift'].numericValue,
          tbt: audits['total-blocking-time'].numericValue
        });
      } catch (error) {
        console.error(`Failed to parse Lighthouse output for ${url}:`, error);
        resolve(null);
      }
    });
  });
}

async function validatePerformance() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Performance Validation (Lighthouse)');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  if (!fs.existsSync(BUILD_DIR)) {
    console.error('❌ Build directory not found.');
    console.error('   Please run "npm run docs:build" first.\n');
    process.exit(1);
  }
  
  // Test key pages
  const keyPages = [
    'index.html',
    '01-getting-started/overview.html',
    '10-tutorials/tutorial-1-hello-pds.html'
  ];
  
  console.log(`Testing ${keyPages.length} key pages\n`);
  console.log('Note: This requires a local server. Starting preview server...\n');
  
  // Start preview server
  const server = spawn('npm', ['run', 'docs:preview'], {
    cwd: DOCS_DIR,
    stdio: 'pipe'
  });
  
  // Wait for server to start
  await new Promise(resolve => setTimeout(resolve, 3000));
  
  try {
    for (const page of keyPages) {
      const url = `http://localhost:4173/${page}`;
      console.log(`Testing: ${page}`);
      
      const result = await runLighthouse(url);
      if (result) {
        results.push(result);
        console.log(`  Performance: ${result.performanceScore.toFixed(0)}`);
        console.log(`  FCP: ${result.fcp.toFixed(2)}s`);
        console.log(`  TTI: ${result.tti.toFixed(2)}s\n`);
      }
    }
  } finally {
    // Stop server
    server.kill();
  }
  
  // Summary
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Summary');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  const avgPerformance = results.reduce((sum, r) => sum + r.performanceScore, 0) / results.length;
  const avgFcp = results.reduce((sum, r) => sum + r.fcp, 0) / results.length;
  const avgTti = results.reduce((sum, r) => sum + r.tti, 0) / results.length;
  
  console.log(`Average performance score: ${avgPerformance.toFixed(0)}`);
  console.log(`Average FCP: ${avgFcp.toFixed(2)}s`);
  console.log(`Average TTI: ${avgTti.toFixed(2)}s\n`);
  
  const passed = avgPerformance >= 90 && avgFcp < 1.5 && avgTti < 3;
  
  if (passed) {
    console.log('✅ PASSED: Performance targets met\n');
  } else {
    console.log('❌ FAILED: Performance targets not met\n');
    if (avgPerformance < 90) {
      console.log(`  - Performance score ${avgPerformance.toFixed(0)} < 90`);
    }
    if (avgFcp >= 1.5) {
      console.log(`  - FCP ${avgFcp.toFixed(2)}s >= 1.5s`);
    }
    if (avgTti >= 3) {
      console.log(`  - TTI ${avgTti.toFixed(2)}s >= 3s`);
    }
    console.log();
  }
  
  // Generate report
  generateReport();
  
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Detailed report saved to: PERFORMANCE_REPORT.md');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  process.exit(passed ? 0 : 1);
}

function generateReport() {
  const lines: string[] = [];
  
  lines.push('# Performance Validation Report');
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('## Summary');
  lines.push('');
  
  const avgPerformance = results.reduce((sum, r) => sum + r.performanceScore, 0) / results.length;
  const avgFcp = results.reduce((sum, r) => sum + r.fcp, 0) / results.length;
  const avgTti = results.reduce((sum, r) => sum + r.tti, 0) / results.length;
  const avgLcp = results.reduce((sum, r) => sum + r.lcp, 0) / results.length;
  
  lines.push(`- Pages tested: ${results.length}`);
  lines.push(`- Average performance score: ${avgPerformance.toFixed(0)}`);
  lines.push(`- Average FCP: ${avgFcp.toFixed(2)}s`);
  lines.push(`- Average TTI: ${avgTti.toFixed(2)}s`);
  lines.push(`- Average LCP: ${avgLcp.toFixed(2)}s`);
  lines.push('');
  
  lines.push('## Targets');
  lines.push('');
  lines.push('- Performance score: ≥ 90');
  lines.push('- First Contentful Paint (FCP): < 1.5s');
  lines.push('- Time to Interactive (TTI): < 3s');
  lines.push('');
  
  lines.push('## Results by Page');
  lines.push('');
  
  for (const result of results) {
    lines.push(`### ${result.url}`);
    lines.push('');
    lines.push(`- Performance Score: ${result.performanceScore.toFixed(0)}`);
    lines.push(`- FCP: ${result.fcp.toFixed(2)}s`);
    lines.push(`- TTI: ${result.tti.toFixed(2)}s`);
    lines.push(`- LCP: ${result.lcp.toFixed(2)}s`);
    lines.push(`- CLS: ${result.cls.toFixed(3)}`);
    lines.push(`- TBT: ${result.tbt.toFixed(0)}ms`);
    lines.push('');
  }
  
  fs.writeFileSync(path.join(DOCS_DIR, 'PERFORMANCE_REPORT.md'), lines.join('\n'));
}

// Run validation
validatePerformance().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

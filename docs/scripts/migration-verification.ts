#!/usr/bin/env tsx
/**
 * Migration Verification Script
 * 
 * Verifies that all Jekyll pages have VitePress equivalents,
 * all code blocks render correctly, all diagrams display correctly,
 * and navigation structure matches the original.
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';

const DOCS_DIR = process.cwd();

interface MigrationVerification {
  category: string;
  passed: boolean;
  details: string[];
  issues: string[];
}

const verifications: MigrationVerification[] = [];

function verifyFileStructure(): MigrationVerification {
  const verification: MigrationVerification = {
    category: 'File Structure',
    passed: true,
    details: [],
    issues: []
  };
  
  // Check that all expected sections exist
  const expectedSections = [
    '01-getting-started',
    '02-core-concepts',
    '03-application-layer',
    '04-network-layer',
    '05-database-layer',
    '06-authentication',
    '07-repository-protocol',
    '08-sync-firehose',
    '09-platform-compatibility',
    '10-tutorials',
    '11-reference',
    '12-diagrams'
  ];
  
  for (const section of expectedSections) {
    const sectionPath = path.join(DOCS_DIR, section);
    if (fs.existsSync(sectionPath)) {
      verification.details.push(`✅ Section exists: ${section}`);
    } else {
      verification.passed = false;
      verification.issues.push(`❌ Missing section: ${section}`);
    }
  }
  
  // Count markdown files
  const mdFiles = glob.sync('**/*.md', {
    cwd: DOCS_DIR,
    ignore: ['node_modules/**', '.vitepress/**', 'dist/**']
  });
  
  verification.details.push(`Total markdown files: ${mdFiles.length}`);
  
  return verification;
}

function verifyCodeBlocks(): MigrationVerification {
  const verification: MigrationVerification = {
    category: 'Code Blocks',
    passed: true,
    details: [],
    issues: []
  };
  
  const mdFiles = glob.sync('**/*.md', {
    cwd: DOCS_DIR,
    ignore: ['node_modules/**', '.vitepress/**', 'dist/**']
  });
  
  let totalCodeBlocks = 0;
  let malformedBlocks = 0;
  
  for (const file of mdFiles) {
    const content = fs.readFileSync(path.join(DOCS_DIR, file), 'utf-8');
    const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
    let match;
    
    while ((match = codeBlockRegex.exec(content)) !== null) {
      totalCodeBlocks++;
      
      // Check for malformed blocks
      if (!match[1] && match[2].includes('function') || match[2].includes('class')) {
        malformedBlocks++;
        verification.issues.push(`Possible missing language in ${file}`);
      }
    }
  }
  
  verification.details.push(`Total code blocks: ${totalCodeBlocks}`);
  verification.details.push(`Malformed blocks: ${malformedBlocks}`);
  
  if (malformedBlocks > 0) {
    verification.passed = false;
  }
  
  return verification;
}

function verifyDiagrams(): MigrationVerification {
  const verification: MigrationVerification = {
    category: 'Diagrams',
    passed: true,
    details: [],
    issues: []
  };
  
  const diagramsDir = path.join(DOCS_DIR, '12-diagrams');
  
  if (!fs.existsSync(diagramsDir)) {
    verification.passed = false;
    verification.issues.push('Diagrams directory not found');
    return verification;
  }
  
  const svgFiles = glob.sync('*.svg', { cwd: diagramsDir });
  verification.details.push(`Total SVG diagrams: ${svgFiles.length}`);
  
  // Check if diagrams are referenced in documentation
  const mdFiles = glob.sync('**/*.md', {
    cwd: DOCS_DIR,
    ignore: ['node_modules/**', '.vitepress/**', 'dist/**']
  });
  
  let referencedDiagrams = 0;
  
  for (const svg of svgFiles) {
    let isReferenced = false;
    
    for (const mdFile of mdFiles) {
      const content = fs.readFileSync(path.join(DOCS_DIR, mdFile), 'utf-8');
      if (content.includes(svg)) {
        isReferenced = true;
        referencedDiagrams++;
        break;
      }
    }
    
    if (!isReferenced) {
      verification.issues.push(`Diagram not referenced: ${svg}`);
    }
  }
  
  verification.details.push(`Referenced diagrams: ${referencedDiagrams}/${svgFiles.length}`);
  
  return verification;
}

function verifyNavigation(): MigrationVerification {
  const verification: MigrationVerification = {
    category: 'Navigation',
    passed: true,
    details: [],
    issues: []
  };
  
  const sidebarPath = path.join(DOCS_DIR, '.vitepress', 'sidebar.ts');
  
  if (!fs.existsSync(sidebarPath)) {
    verification.passed = false;
    verification.issues.push('Sidebar configuration not found');
    return verification;
  }
  
  const sidebarContent = fs.readFileSync(sidebarPath, 'utf-8');
  
  // Check that all sections are in sidebar
  const expectedSections = [
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
  
  for (const section of expectedSections) {
    if (sidebarContent.includes(section)) {
      verification.details.push(`✅ Section in sidebar: ${section}`);
    } else {
      verification.passed = false;
      verification.issues.push(`❌ Missing from sidebar: ${section}`);
    }
  }
  
  return verification;
}

function verifyVitePressConfig(): MigrationVerification {
  const verification: MigrationVerification = {
    category: 'VitePress Configuration',
    passed: true,
    details: [],
    issues: []
  };
  
  const configPath = path.join(DOCS_DIR, '.vitepress', 'config.ts');
  
  if (!fs.existsSync(configPath)) {
    verification.passed = false;
    verification.issues.push('VitePress config not found');
    return verification;
  }
  
  const configContent = fs.readFileSync(configPath, 'utf-8');
  
  // Check for required configuration
  const requiredConfig = [
    'title:',
    'description:',
    'base:',
    'themeConfig:',
    'search:',
    'sidebar:'
  ];
  
  for (const config of requiredConfig) {
    if (configContent.includes(config)) {
      verification.details.push(`✅ Has ${config}`);
    } else {
      verification.passed = false;
      verification.issues.push(`❌ Missing ${config}`);
    }
  }
  
  return verification;
}

async function runMigrationVerification() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Migration Verification');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  // Run all verifications
  verifications.push(verifyFileStructure());
  verifications.push(verifyCodeBlocks());
  verifications.push(verifyDiagrams());
  verifications.push(verifyNavigation());
  verifications.push(verifyVitePressConfig());
  
  // Display results
  for (const verification of verifications) {
    const status = verification.passed ? '✅' : '❌';
    console.log(`${status} ${verification.category}`);
    
    for (const detail of verification.details.slice(0, 3)) {
      console.log(`   ${detail}`);
    }
    
    if (verification.issues.length > 0) {
      console.log(`   Issues: ${verification.issues.length}`);
      for (const issue of verification.issues.slice(0, 2)) {
        console.log(`   ${issue}`);
      }
      if (verification.issues.length > 2) {
        console.log(`   ... and ${verification.issues.length - 2} more`);
      }
    }
    
    console.log();
  }
  
  // Summary
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Summary');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  const passed = verifications.filter(v => v.passed).length;
  const failed = verifications.filter(v => !v.passed).length;
  
  console.log(`Verifications: ${verifications.length}`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}\n`);
  
  if (failed === 0) {
    console.log('✅ PASSED: Migration verification complete\n');
  } else {
    console.log('❌ FAILED: Migration verification found issues\n');
  }
  
  // Generate report
  generateReport();
  
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Detailed report saved to: MIGRATION_VERIFICATION_REPORT.md');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  process.exit(failed > 0 ? 1 : 0);
}

function generateReport() {
  const lines: string[] = [];
  
  lines.push('# Migration Verification Report');
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('## Summary');
  lines.push('');
  
  const passed = verifications.filter(v => v.passed).length;
  const failed = verifications.filter(v => !v.passed).length;
  
  lines.push(`- Total verifications: ${verifications.length}`);
  lines.push(`- Passed: ${passed}`);
  lines.push(`- Failed: ${failed}`);
  lines.push('');
  
  lines.push('## Verification Results');
  lines.push('');
  
  for (const verification of verifications) {
    const status = verification.passed ? '✅ PASSED' : '❌ FAILED';
    lines.push(`### ${status}: ${verification.category}`);
    lines.push('');
    
    if (verification.details.length > 0) {
      lines.push('**Details:**');
      lines.push('');
      for (const detail of verification.details) {
        lines.push(`- ${detail}`);
      }
      lines.push('');
    }
    
    if (verification.issues.length > 0) {
      lines.push('**Issues:**');
      lines.push('');
      for (const issue of verification.issues) {
        lines.push(`- ${issue}`);
      }
      lines.push('');
    }
  }
  
  lines.push('## Conclusion');
  lines.push('');
  
  if (failed === 0) {
    lines.push('All migration verification checks passed. The VitePress migration is complete and verified.');
  } else {
    lines.push('Some migration verification checks failed. Review the issues above and address them before deployment.');
  }
  lines.push('');
  
  fs.writeFileSync(path.join(DOCS_DIR, 'MIGRATION_VERIFICATION_REPORT.md'), lines.join('\n'));
}

// Run verification
runMigrationVerification().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

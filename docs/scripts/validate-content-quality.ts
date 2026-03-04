#!/usr/bin/env ts-node
/**
 * Content Quality and Consistency Validation Script
 * 
 * This script validates that all expanded documentation content meets quality standards:
 * - Consistent voice and style
 * - Terminology matches GLOSSARY.md
 * - Progressive complexity from simple to advanced
 * - All code examples have explanatory context
 * - Tutorial structure completeness
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';

interface ValidationIssue {
  file: string;
  line?: number;
  severity: 'error' | 'warning' | 'info';
  category: string;
  message: string;
}

interface TutorialStructure {
  hasPrerequisites: boolean;
  hasLearningObjectives: boolean;
  hasOverview: boolean;
  hasTroubleshooting: boolean;
  hasNextSteps: boolean;
  hasEstimatedTime: boolean;
  hasSummary: boolean;
}

interface ContentMetrics {
  totalFiles: number;
  tutorialsChecked: number;
  codeBlocksChecked: number;
  terminologyIssues: number;
  structureIssues: number;
  styleIssues: number;
}

class ContentQualityValidator {
  private issues: ValidationIssue[] = [];
  private metrics: ContentMetrics = {
    totalFiles: 0,
    tutorialsChecked: 0,
    codeBlocksChecked: 0,
    terminologyIssues: 0,
    structureIssues: 0,
    styleIssues: 0,
  };
  
  private glossaryTerms: Map<string, string> = new Map();
  private commonMisspellings: Map<string, string> = new Map([
    ['merkle tree', 'Merkle Search Tree (MST)'],
    ['merkle-tree', 'Merkle Search Tree (MST)'],
    ['dag cbor', 'DAG-CBOR'],
    ['dag/cbor', 'DAG-CBOR'],
    ['content identifier', 'CID (Content Identifier)'],
    ['personal data server', 'PDS (Personal Data Server)'],
    ['json web token', 'JWT (JSON Web Token)'],
    ['oauth2', 'OAuth 2.0'],
    ['oauth 2', 'OAuth 2.0'],
    ['websocket', 'WebSocket'],
    ['web socket', 'WebSocket'],
  ]);

  async validate(): Promise<void> {
    console.log('🔍 Starting content quality validation...\n');
    
    // Load glossary terms
    await this.loadGlossary();
    
    // Find all markdown files
    const files = await glob('**/*.md', {
      ignore: ['node_modules/**', '.vitepress/**'],
    });
    
    this.metrics.totalFiles = files.length;
    
    // Validate each file
    for (const file of files) {
      await this.validateFile(file);
    }
    
    // Generate report
    this.generateReport();
  }

  private async loadGlossary(): Promise<void> {
    const glossaryPath = 'GLOSSARY.md';
    if (!fs.existsSync(glossaryPath)) {
      console.warn('⚠️  GLOSSARY.md not found');
      return;
    }
    
    const content = fs.readFileSync(glossaryPath, 'utf-8');
    const lines = content.split('\n');
    
    for (const line of lines) {
      // Match glossary entries like: **Term** — Definition
      const match = line.match(/^\*\*([^*]+)\*\*\s*[—-]\s*(.+)$/);
      if (match) {
        const term = match[1].trim();
        const definition = match[2].trim();
        this.glossaryTerms.set(term.toLowerCase(), term);
      }
    }
    
    console.log(`📚 Loaded ${this.glossaryTerms.size} glossary terms\n`);
  }

  private async validateFile(filePath: string): Promise<void> {
    const content = fs.readFileSync(filePath, 'utf-8');
    const lines = content.split('\n');
    
    // Check if this is a tutorial
    if (filePath.includes('/10-tutorials/')) {
      this.validateTutorialStructure(filePath, content);
      this.metrics.tutorialsChecked++;
    }
    
    // Validate code blocks have context
    this.validateCodeBlockContext(filePath, lines);
    
    // Check terminology consistency
    this.validateTerminology(filePath, content);
    
    // Check style consistency
    this.validateStyle(filePath, lines);
    
    // Check progressive complexity
    this.validateComplexity(filePath, content);
  }

  private validateTutorialStructure(filePath: string, content: string): void {
    const structure: TutorialStructure = {
      hasPrerequisites: /##\s+Prerequisites/i.test(content),
      hasLearningObjectives: /##\s+Learning Objectives/i.test(content) || /##\s+What You'll Learn/i.test(content),
      hasOverview: /##\s+Overview/i.test(content) || /##\s+What You'll Build/i.test(content),
      hasTroubleshooting: /##\s+Troubleshooting/i.test(content) || /##\s+Common Issues/i.test(content),
      hasNextSteps: /##\s+Next Steps/i.test(content),
      hasEstimatedTime: /Estimated time:/i.test(content) || /Duration:/i.test(content),
      hasSummary: /##\s+Summary/i.test(content) || /##\s+Conclusion/i.test(content),
    };
    
    const missing: string[] = [];
    if (!structure.hasPrerequisites) missing.push('Prerequisites');
    if (!structure.hasLearningObjectives) missing.push('Learning Objectives');
    if (!structure.hasOverview) missing.push('Overview/What You\'ll Build');
    if (!structure.hasTroubleshooting) missing.push('Troubleshooting');
    if (!structure.hasNextSteps) missing.push('Next Steps');
    if (!structure.hasEstimatedTime) missing.push('Estimated Time');
    if (!structure.hasSummary) missing.push('Summary');
    
    if (missing.length > 0) {
      this.issues.push({
        file: filePath,
        severity: 'error',
        category: 'Tutorial Structure',
        message: `Missing required sections: ${missing.join(', ')}`,
      });
      this.metrics.structureIssues++;
    }
  }

  private validateCodeBlockContext(filePath: string, lines: string[]): void {
    let inCodeBlock = false;
    let codeBlockStart = 0;
    let hasContextBefore = false;
    let hasContextAfter = false;
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      
      if (line.startsWith('```')) {
        if (!inCodeBlock) {
          // Starting code block
          inCodeBlock = true;
          codeBlockStart = i;
          
          // Check if there's explanatory text before (within 5 lines)
          hasContextBefore = false;
          for (let j = Math.max(0, i - 5); j < i; j++) {
            const prevLine = lines[j].trim();
            if (prevLine.length > 20 && !prevLine.startsWith('#') && !prevLine.startsWith('```')) {
              hasContextBefore = true;
              break;
            }
          }
        } else {
          // Ending code block
          inCodeBlock = false;
          this.metrics.codeBlocksChecked++;
          
          // Check if there's explanatory text after (within 5 lines)
          hasContextAfter = false;
          for (let j = i + 1; j < Math.min(lines.length, i + 6); j++) {
            const nextLine = lines[j].trim();
            if (nextLine.length > 20 && !nextLine.startsWith('#') && !nextLine.startsWith('```')) {
              hasContextAfter = true;
              break;
            }
          }
          
          // Code blocks should have context either before or after
          if (!hasContextBefore && !hasContextAfter) {
            this.issues.push({
              file: filePath,
              line: codeBlockStart + 1,
              severity: 'warning',
              category: 'Code Context',
              message: 'Code block lacks explanatory context before or after',
            });
          }
        }
      }
    }
  }

  private validateTerminology(filePath: string, content: string): void {
    // Check for common misspellings or inconsistent terminology
    for (const [incorrect, correct] of this.commonMisspellings) {
      const regex = new RegExp(`\\b${incorrect}\\b`, 'gi');
      const matches = content.match(regex);
      
      if (matches) {
        this.issues.push({
          file: filePath,
          severity: 'warning',
          category: 'Terminology',
          message: `Found "${incorrect}" - should use "${correct}" for consistency`,
        });
        this.metrics.terminologyIssues++;
      }
    }
    
    // Check for undefined acronyms (acronym used without definition)
    const acronymPattern = /\b([A-Z]{2,})\b/g;
    const acronyms = content.match(acronymPattern) || [];
    const uniqueAcronyms = [...new Set(acronyms)];
    
    for (const acronym of uniqueAcronyms) {
      // Skip common words that happen to be all caps
      if (['OK', 'ID', 'URL', 'API', 'CLI', 'UI', 'VM'].includes(acronym)) {
        continue;
      }
      
      // Check if acronym is defined in glossary
      if (!this.glossaryTerms.has(acronym.toLowerCase())) {
        // Check if it's defined in the document itself
        const definitionPattern = new RegExp(`${acronym}\\s*[—-]\\s*`, 'i');
        if (!definitionPattern.test(content)) {
          this.issues.push({
            file: filePath,
            severity: 'info',
            category: 'Terminology',
            message: `Acronym "${acronym}" used but not defined in GLOSSARY.md or document`,
          });
        }
      }
    }
  }

  private validateStyle(filePath: string, lines: string[]): void {
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      
      // Check for overly long lines (excluding code blocks and links)
      if (!line.startsWith('```') && !line.includes('](') && line.length > 120) {
        this.issues.push({
          file: filePath,
          line: i + 1,
          severity: 'info',
          category: 'Style',
          message: `Line exceeds 120 characters (${line.length} chars) - consider breaking for readability`,
        });
      }
      
      // Check for inconsistent heading style
      if (line.startsWith('#')) {
        // Headings should have space after #
        if (!/^#+\s/.test(line)) {
          this.issues.push({
            file: filePath,
            line: i + 1,
            severity: 'warning',
            category: 'Style',
            message: 'Heading should have space after # symbols',
          });
          this.metrics.styleIssues++;
        }
      }
      
      // Check for passive voice indicators (informational only)
      const passiveIndicators = ['is being', 'was being', 'has been', 'have been', 'had been', 'will be'];
      for (const indicator of passiveIndicators) {
        if (line.toLowerCase().includes(indicator)) {
          this.issues.push({
            file: filePath,
            line: i + 1,
            severity: 'info',
            category: 'Style',
            message: `Consider active voice instead of passive: "${indicator}"`,
          });
          break; // Only report once per line
        }
      }
    }
  }

  private validateComplexity(filePath: string, content: string): void {
    // Check if documentation builds concepts progressively
    // This is a heuristic check - look for "basic", "simple", "introduction" early
    // and "advanced", "complex", "optimization" later
    
    const basicTerms = ['basic', 'simple', 'introduction', 'getting started', 'hello', 'first'];
    const advancedTerms = ['advanced', 'complex', 'optimization', 'performance', 'production'];
    
    let firstBasicPos = Infinity;
    let firstAdvancedPos = Infinity;
    
    for (const term of basicTerms) {
      const pos = content.toLowerCase().indexOf(term);
      if (pos !== -1 && pos < firstBasicPos) {
        firstBasicPos = pos;
      }
    }
    
    for (const term of advancedTerms) {
      const pos = content.toLowerCase().indexOf(term);
      if (pos !== -1 && pos < firstAdvancedPos) {
        firstAdvancedPos = pos;
      }
    }
    
    // If advanced terms appear before basic terms, flag it
    if (firstAdvancedPos < firstBasicPos && firstAdvancedPos !== Infinity) {
      this.issues.push({
        file: filePath,
        severity: 'info',
        category: 'Complexity',
        message: 'Advanced concepts may appear before basic concepts - verify progressive complexity',
      });
    }
  }

  private generateReport(): void {
    console.log('\n' + '='.repeat(80));
    console.log('📊 CONTENT QUALITY VALIDATION REPORT');
    console.log('='.repeat(80) + '\n');
    
    // Summary metrics
    console.log('📈 Metrics:');
    console.log(`   Total files validated: ${this.metrics.totalFiles}`);
    console.log(`   Tutorials checked: ${this.metrics.tutorialsChecked}`);
    console.log(`   Code blocks checked: ${this.metrics.codeBlocksChecked}`);
    console.log(`   Total issues found: ${this.issues.length}`);
    console.log();
    
    // Issues by severity
    const errors = this.issues.filter(i => i.severity === 'error');
    const warnings = this.issues.filter(i => i.severity === 'warning');
    const info = this.issues.filter(i => i.severity === 'info');
    
    console.log('🚨 Issues by Severity:');
    console.log(`   Errors: ${errors.length}`);
    console.log(`   Warnings: ${warnings.length}`);
    console.log(`   Info: ${info.length}`);
    console.log();
    
    // Issues by category
    const byCategory = new Map<string, number>();
    for (const issue of this.issues) {
      byCategory.set(issue.category, (byCategory.get(issue.category) || 0) + 1);
    }
    
    console.log('📂 Issues by Category:');
    for (const [category, count] of byCategory) {
      console.log(`   ${category}: ${count}`);
    }
    console.log();
    
    // Detailed issues
    if (errors.length > 0) {
      console.log('❌ ERRORS (must fix):');
      for (const issue of errors) {
        const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
        console.log(`   ${location}`);
        console.log(`      [${issue.category}] ${issue.message}`);
      }
      console.log();
    }
    
    if (warnings.length > 0) {
      console.log('⚠️  WARNINGS (should fix):');
      for (const issue of warnings.slice(0, 20)) { // Limit to first 20
        const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
        console.log(`   ${location}`);
        console.log(`      [${issue.category}] ${issue.message}`);
      }
      if (warnings.length > 20) {
        console.log(`   ... and ${warnings.length - 20} more warnings`);
      }
      console.log();
    }
    
    if (info.length > 0) {
      console.log(`ℹ️  INFO (${info.length} suggestions - showing first 10):`);
      for (const issue of info.slice(0, 10)) {
        const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
        console.log(`   ${location}`);
        console.log(`      [${issue.category}] ${issue.message}`);
      }
      console.log();
    }
    
    // Overall assessment
    console.log('='.repeat(80));
    if (errors.length === 0 && warnings.length === 0) {
      console.log('✅ PASS: Content quality validation passed!');
    } else if (errors.length === 0) {
      console.log('⚠️  PASS WITH WARNINGS: No critical issues, but improvements recommended');
    } else {
      console.log('❌ FAIL: Critical issues found that must be addressed');
    }
    console.log('='.repeat(80) + '\n');
    
    // Write detailed report to file
    this.writeDetailedReport();
  }

  private writeDetailedReport(): void {
    const reportPath = 'CONTENT_QUALITY_REPORT.md';
    let report = '# Content Quality Validation Report\n\n';
    report += `Generated: ${new Date().toISOString()}\n\n`;
    
    report += '## Summary\n\n';
    report += `- Total files validated: ${this.metrics.totalFiles}\n`;
    report += `- Tutorials checked: ${this.metrics.tutorialsChecked}\n`;
    report += `- Code blocks checked: ${this.metrics.codeBlocksChecked}\n`;
    report += `- Total issues: ${this.issues.length}\n\n`;
    
    const errors = this.issues.filter(i => i.severity === 'error');
    const warnings = this.issues.filter(i => i.severity === 'warning');
    const info = this.issues.filter(i => i.severity === 'info');
    
    report += '## Issues by Severity\n\n';
    report += `- Errors: ${errors.length}\n`;
    report += `- Warnings: ${warnings.length}\n`;
    report += `- Info: ${info.length}\n\n`;
    
    if (errors.length > 0) {
      report += '## Errors\n\n';
      for (const issue of errors) {
        const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
        report += `### ${location}\n\n`;
        report += `**Category:** ${issue.category}\n\n`;
        report += `**Message:** ${issue.message}\n\n`;
      }
    }
    
    if (warnings.length > 0) {
      report += '## Warnings\n\n';
      for (const issue of warnings) {
        const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
        report += `### ${location}\n\n`;
        report += `**Category:** ${issue.category}\n\n`;
        report += `**Message:** ${issue.message}\n\n`;
      }
    }
    
    if (info.length > 0) {
      report += '## Informational\n\n';
      for (const issue of info) {
        const location = issue.line ? `${issue.file}:${issue.line}` : issue.file;
        report += `- ${location}: [${issue.category}] ${issue.message}\n`;
      }
      report += '\n';
    }
    
    fs.writeFileSync(reportPath, report);
    console.log(`📄 Detailed report written to: ${reportPath}\n`);
  }
}

// Main execution
async function main() {
  const validator = new ContentQualityValidator();
  await validator.validate();
}

main().catch(error => {
  console.error('❌ Validation failed:', error);
  process.exit(1);
});

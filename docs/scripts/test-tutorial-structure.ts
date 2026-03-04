#!/usr/bin/env ts-node
/**
 * Property-Based Test: Tutorial Structure Completeness
 * 
 * Property 5: For any tutorial in the 10-tutorials section, the tutorial SHALL contain
 * all required sections: prerequisites, learning objectives, overview, troubleshooting,
 * next steps, estimated time, and summary.
 * 
 * Validates: Requirements 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.10
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';

interface TutorialStructure {
  file: string;
  hasPrerequisites: boolean;
  hasLearningObjectives: boolean;
  hasOverview: boolean;
  hasTroubleshooting: boolean;
  hasNextSteps: boolean;
  hasEstimatedTime: boolean;
  hasSummary: boolean;
}

interface ValidationResult {
  passed: boolean;
  tutorialsChecked: number;
  failures: Array<{
    tutorial: string;
    missingSections: string[];
  }>;
}

async function validateTutorialStructure(): Promise<ValidationResult> {
  console.log('🧪 Property 5: Tutorial Structure Completeness\n');
  console.log('Testing that all tutorials have required sections...\n');
  
  // Find all tutorial files
  const tutorialFiles = await glob('10-tutorials/tutorial-*.md');
  
  if (tutorialFiles.length === 0) {
    throw new Error('No tutorial files found in 10-tutorials/');
  }
  
  console.log(`Found ${tutorialFiles.length} tutorials to validate\n`);
  
  const failures: Array<{ tutorial: string; missingSections: string[] }> = [];
  
  // Validate each tutorial
  for (const file of tutorialFiles) {
    const content = fs.readFileSync(file, 'utf-8');
    const structure = analyzeTutorialStructure(file, content);
    
    const missing = getMissingSections(structure);
    
    if (missing.length > 0) {
      failures.push({
        tutorial: file,
        missingSections: missing,
      });
      console.log(`❌ ${file}: Missing ${missing.join(', ')}`);
    } else {
      console.log(`✅ ${file}: All required sections present`);
    }
  }
  
  console.log();
  
  return {
    passed: failures.length === 0,
    tutorialsChecked: tutorialFiles.length,
    failures,
  };
}

function analyzeTutorialStructure(file: string, content: string): TutorialStructure {
  return {
    file,
    hasPrerequisites: /##\s+Prerequisites/i.test(content),
    hasLearningObjectives: 
      /\*\*Learning Objectives:\*\*/i.test(content) || 
      /##\s+Learning Objectives/i.test(content) ||
      /##\s+What You'll Learn/i.test(content),
    hasOverview: 
      /##\s+Overview/i.test(content) || 
      /##\s+What You'll Build/i.test(content),
    hasTroubleshooting: 
      /##\s+Troubleshooting/i.test(content) || 
      /##\s+Common Issues/i.test(content),
    hasNextSteps: /##\s+Next Steps/i.test(content),
    hasEstimatedTime: 
      /\*\*Estimated Time:\*\*/i.test(content) || 
      /\*\*Duration:\*\*/i.test(content) ||
      /Estimated time:/i.test(content),
    hasSummary: 
      /##\s+Summary/i.test(content) || 
      /##\s+Conclusion/i.test(content),
  };
}

function getMissingSections(structure: TutorialStructure): string[] {
  const missing: string[] = [];
  
  if (!structure.hasPrerequisites) missing.push('Prerequisites');
  if (!structure.hasLearningObjectives) missing.push('Learning Objectives');
  if (!structure.hasOverview) missing.push('Overview');
  if (!structure.hasTroubleshooting) missing.push('Troubleshooting');
  if (!structure.hasNextSteps) missing.push('Next Steps');
  if (!structure.hasEstimatedTime) missing.push('Estimated Time');
  if (!structure.hasSummary) missing.push('Summary');
  
  return missing;
}

function generateReport(result: ValidationResult): void {
  console.log('='.repeat(80));
  console.log('📊 PROPERTY TEST RESULTS');
  console.log('='.repeat(80));
  console.log();
  console.log(`Property: Tutorial Structure Completeness`);
  console.log(`Tutorials Checked: ${result.tutorialsChecked}`);
  console.log(`Status: ${result.passed ? '✅ PASSED' : '❌ FAILED'}`);
  console.log();
  
  if (result.failures.length > 0) {
    console.log('Failures:');
    for (const failure of result.failures) {
      console.log(`  ${failure.tutorial}:`);
      console.log(`    Missing: ${failure.missingSections.join(', ')}`);
    }
    console.log();
  }
  
  console.log('='.repeat(80));
  
  // Write report
  const reportPath = 'TUTORIAL_STRUCTURE_TEST_REPORT.md';
  let report = '# Tutorial Structure Completeness Test Report\n\n';
  report += `**Property 5:** For any tutorial in the 10-tutorials section, the tutorial SHALL contain all required sections.\n\n`;
  report += `**Generated:** ${new Date().toISOString()}\n\n`;
  report += `## Results\n\n`;
  report += `- Tutorials Checked: ${result.tutorialsChecked}\n`;
  report += `- Status: ${result.passed ? '✅ PASSED' : '❌ FAILED'}\n`;
  report += `- Failures: ${result.failures.length}\n\n`;
  
  if (result.failures.length > 0) {
    report += `## Failures\n\n`;
    for (const failure of result.failures) {
      report += `### ${failure.tutorial}\n\n`;
      report += `Missing sections:\n`;
      for (const section of failure.missingSections) {
        report += `- ${section}\n`;
      }
      report += '\n';
    }
  } else {
    report += `## All Tutorials Pass\n\n`;
    report += `All ${result.tutorialsChecked} tutorials contain the required sections:\n`;
    report += `- Prerequisites\n`;
    report += `- Learning Objectives\n`;
    report += `- Overview\n`;
    report += `- Troubleshooting\n`;
    report += `- Next Steps\n`;
    report += `- Estimated Time\n`;
    report += `- Summary\n`;
  }
  
  fs.writeFileSync(reportPath, report);
  console.log(`\n📄 Report written to: ${reportPath}\n`);
}

// Main execution
async function main() {
  try {
    const result = await validateTutorialStructure();
    generateReport(result);
    
    if (!result.passed) {
      process.exit(1);
    }
  } catch (error) {
    console.error('❌ Test failed:', error);
    process.exit(1);
  }
}

main();

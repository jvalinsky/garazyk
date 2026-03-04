#!/usr/bin/env node
/**
 * Content Expansion Framework
 * 
 * This tool expands existing documentation with comprehensive explanations,
 * "Why this matters" sections, troubleshooting guidance, and real-world examples.
 */

import * as fs from 'fs';
import * as path from 'path';

// ============================================================================
// Interfaces
// ============================================================================

export interface ContentExpansionRule {
  pattern: RegExp;
  expansion: (match: string, context: FileContext) => string;
}

export interface FileContext {
  filePath: string;
  section: string;
  existingContent: string;
  codeBlocks: CodeBlock[];
  headings: string[];
}

export interface CodeBlock {
  language: string;
  code: string;
  lineNumber: number;
  title?: string;
}

export interface ExpansionOptions {
  sourceDir: string;
  targetFiles?: string[];
  dryRun?: boolean;
  verbose?: boolean;
}

export interface ExpansionResult {
  filesProcessed: number;
  filesExpanded: number;
  sectionsAdded: number;
  errors: string[];
  warnings: string[];
}

// ============================================================================
// Content Expander Class
// ============================================================================

export class ContentExpander {
  private options: ExpansionOptions;
  private result: ExpansionResult;

  constructor(options: ExpansionOptions) {
    this.options = options;
    this.result = {
      filesProcessed: 0,
      filesExpanded: 0,
      sectionsAdded: 0,
      errors: [],
      warnings: []
    };
  }

  /**
   * Expand a single file with comprehensive content
   */
  async expandFile(filePath: string): Promise<string> {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const context = this.buildFileContext(filePath, content);
      
      let expandedContent = content;
      
      // Add explanations for code blocks
      expandedContent = this.addCodeExplanations(expandedContent, context);
      
      // Add "Why this matters" sections
      expandedContent = this.addWhySections(expandedContent, context);
      
      // Add troubleshooting sections
      expandedContent = this.addTroubleshooting(expandedContent, context);
      
      // Add real-world examples
      expandedContent = this.addRealWorldExamples(expandedContent, context);
      
      return expandedContent;
    } catch (error) {
      this.result.errors.push(`Error expanding ${filePath}: ${error}`);
      throw error;
    }
  }

  /**
   * Build context for a file
   */
  private buildFileContext(filePath: string, content: string): FileContext {
    const section = this.extractSection(filePath);
    const codeBlocks = this.extractCodeBlocks(content);
    const headings = this.extractHeadings(content);

    return {
      filePath,
      section,
      existingContent: content,
      codeBlocks,
      headings
    };
  }

  /**
   * Extract section from file path (e.g., "01-getting-started")
   */
  private extractSection(filePath: string): string {
    const match = filePath.match(/\/(\d{2}-[^/]+)\//);
    return match ? match[1] : 'unknown';
  }

  /**
   * Extract code blocks from content
   */
  private extractCodeBlocks(content: string): CodeBlock[] {
    const blocks: CodeBlock[] = [];
    const lines = content.split('\n');
    let inCodeBlock = false;
    let currentBlock: Partial<CodeBlock> = {};
    let lineNumber = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      
      if (line.startsWith('```')) {
        if (!inCodeBlock) {
          // Start of code block
          const match = line.match(/```(\w+)(?:\s+\[([^\]]+)\])?/);
          currentBlock = {
            language: match?.[1] || 'text',
            title: match?.[2],
            code: '',
            lineNumber: i + 1
          };
          inCodeBlock = true;
        } else {
          // End of code block
          blocks.push(currentBlock as CodeBlock);
          currentBlock = {};
          inCodeBlock = false;
        }
      } else if (inCodeBlock) {
        currentBlock.code = (currentBlock.code || '') + line + '\n';
      }
    }

    return blocks;
  }

  /**
   * Extract headings from content
   */
  private extractHeadings(content: string): string[] {
    const headings: string[] = [];
    const lines = content.split('\n');
    
    for (const line of lines) {
      if (line.match(/^#{1,6}\s+/)) {
        headings.push(line.replace(/^#+\s+/, '').trim());
      }
    }
    
    return headings;
  }

  /**
   * Add explanations for code blocks
   */
  private addCodeExplanations(content: string, context: FileContext): string {
    // This is a template - actual implementation would analyze code
    // and insert explanations before or after code blocks
    return content;
  }

  /**
   * Add "Why this matters" sections
   */
  private addWhySections(content: string, context: FileContext): string {
    // Template for adding importance explanations
    return content;
  }

  /**
   * Add troubleshooting sections
   */
  private addTroubleshooting(content: string, context: FileContext): string {
    // Template for adding common issues and solutions
    return content;
  }

  /**
   * Add real-world examples
   */
  private addRealWorldExamples(content: string, context: FileContext): string {
    // Template for adding practical usage examples
    return content;
  }

  /**
   * Get expansion result
   */
  getResult(): ExpansionResult {
    return this.result;
  }
}

// ============================================================================
// Expansion Templates
// ============================================================================

export const expansionTemplates = {
  /**
   * Template for code explanation
   */
  codeExplanation: (codeBlock: CodeBlock, keyPoints: string[]): string => {
    return `
### Understanding the Code

${keyPoints.map(point => `- ${point}`).join('\n')}

**Key Concepts:**

This code demonstrates the core implementation pattern used throughout the September PDS codebase.
`;
  },

  /**
   * Template for "Why this matters"
   */
  whyItMatters: (topic: string, importance: string, productionRelevance: string): string => {
    return `
### Why This Matters

${importance}

In production systems, ${productionRelevance}.
`;
  },

  /**
   * Template for troubleshooting
   */
  troubleshooting: (problems: Array<{problem: string, solution: string}>): string => {
    const sections = problems.map(({problem, solution}) => `
**Problem:** ${problem}

**Solution:** ${solution}
`).join('\n');

    return `
### Common Issues and Solutions

${sections}
`;
  },

  /**
   * Template for real-world example
   */
  realWorldExample: (scenario: string, implementation: string): string => {
    return `
### Real-World Example

**Scenario:** ${scenario}

**Implementation:**

${implementation}
`;
  },

  /**
   * Template for prerequisites
   */
  prerequisites: (items: string[]): string => {
    return `
## Prerequisites

Before starting this tutorial, you should have:

${items.map(item => `- ${item}`).join('\n')}
`;
  },

  /**
   * Template for learning objectives
   */
  learningObjectives: (objectives: string[]): string => {
    return `
## Learning Objectives

By the end of this tutorial, you will:

${objectives.map(obj => `- ${obj}`).join('\n')}
`;
  },

  /**
   * Template for "What you'll build"
   */
  whatYoullBuild: (description: string, features: string[]): string => {
    return `
## What You'll Build

${description}

**Features:**

${features.map(feature => `- ${feature}`).join('\n')}
`;
  },

  /**
   * Template for next steps
   */
  nextSteps: (steps: Array<{title: string, link: string}>): string => {
    return `
## Next Steps

${steps.map(({title, link}) => `- [${title}](${link})`).join('\n')}
`;
  },

  /**
   * Template for summary
   */
  summary: (keyTakeaways: string[]): string => {
    return `
## Summary

In this tutorial, you learned:

${keyTakeaways.map(takeaway => `- ${takeaway}`).join('\n')}
`;
  }
};

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Analyze code to extract key points
 */
export function analyzeCode(codeBlock: CodeBlock): string[] {
  const keyPoints: string[] = [];
  
  // Simple heuristics for Objective-C code
  if (codeBlock.code.includes('@interface')) {
    keyPoints.push('Defines a class interface with properties and methods');
  }
  if (codeBlock.code.includes('@implementation')) {
    keyPoints.push('Implements the class methods and logic');
  }
  if (codeBlock.code.includes('dispatch_')) {
    keyPoints.push('Uses Grand Central Dispatch for concurrency');
  }
  if (codeBlock.code.includes('sqlite3_')) {
    keyPoints.push('Interacts with SQLite database');
  }
  
  return keyPoints;
}

/**
 * Extract design decision from code
 */
export function explainDesignDecision(codeBlock: CodeBlock): string {
  // Template - would analyze code patterns
  return 'This approach was chosen for its balance of performance and maintainability.';
}

// ============================================================================
// CLI Entry Point
// ============================================================================

if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length === 0) {
    console.log('Usage: expand-content.ts <file-path>');
    console.log('');
    console.log('Example: expand-content.ts docs/10-tutorials/tutorial-1-hello-pds.md');
    process.exit(1);
  }
  
  const filePath = args[0];
  const expander = new ContentExpander({ sourceDir: path.dirname(filePath) });
  
  expander.expandFile(filePath)
    .then(expandedContent => {
      console.log('Expanded content:');
      console.log(expandedContent);
    })
    .catch(error => {
      console.error('Error:', error);
      process.exit(1);
    });
}

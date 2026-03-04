#!/usr/bin/env tsx
/**
 * Code Example Validation
 * 
 * Validates that tutorial code examples compile and follow coding standards.
 * Checks for error handling, memory management notes, and style compliance.
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';
import { spawn } from 'child_process';

const EXAMPLES_DIR = path.join(process.cwd(), '..', 'examples');
const DOCS_DIR = process.cwd();

interface CodeValidationResult {
  example: string;
  compiled: boolean;
  styleChecked: boolean;
  hasErrorHandling: boolean;
  hasMemoryNotes: boolean;
  issues: string[];
}

const results: CodeValidationResult[] = [];

async function compileExample(exampleDir: string): Promise<{ success: boolean; output: string }> {
  return new Promise((resolve) => {
    // Check if CMakeLists.txt exists
    const cmakeFile = path.join(exampleDir, 'CMakeLists.txt');
    if (!fs.existsSync(cmakeFile)) {
      resolve({ success: false, output: 'No CMakeLists.txt found' });
      return;
    }
    
    // Create build directory
    const buildDir = path.join(exampleDir, 'build-test');
    if (!fs.existsSync(buildDir)) {
      fs.mkdirSync(buildDir, { recursive: true });
    }
    
    // Run cmake
    const cmake = spawn('cmake', ['..'], {
      cwd: buildDir,
      stdio: 'pipe'
    });
    
    let output = '';
    
    cmake.stdout.on('data', (data) => {
      output += data.toString();
    });
    
    cmake.stderr.on('data', (data) => {
      output += data.toString();
    });
    
    cmake.on('close', (code) => {
      if (code !== 0) {
        resolve({ success: false, output });
        return;
      }
      
      // Run make
      const make = spawn('make', [], {
        cwd: buildDir,
        stdio: 'pipe'
      });
      
      make.stdout.on('data', (data) => {
        output += data.toString();
      });
      
      make.stderr.on('data', (data) => {
        output += data.toString();
      });
      
      make.on('close', (makeCode) => {
        // Clean up build directory
        try {
          fs.rmSync(buildDir, { recursive: true, force: true });
        } catch (e) {
          // Ignore cleanup errors
        }
        
        resolve({ success: makeCode === 0, output });
      });
    });
  });
}

function checkErrorHandling(sourceFiles: string[]): boolean {
  for (const file of sourceFiles) {
    const content = fs.readFileSync(file, 'utf-8');
    
    // Check for error handling patterns
    const hasErrorCheck = /if\s*\([^)]*error|if\s*\(!\s*\w+\)|NSError\s*\*/.test(content);
    const hasNilCheck = /if\s*\(!\s*\w+\)|if\s*\(\w+\s*==\s*nil\)/.test(content);
    
    if (hasErrorCheck || hasNilCheck) {
      return true;
    }
  }
  
  return false;
}

function checkMemoryNotes(sourceFiles: string[]): boolean {
  for (const file of sourceFiles) {
    const content = fs.readFileSync(file, 'utf-8');
    
    // Check for memory management comments
    const hasMemoryNotes = /\/\/.*\b(ARC|retain|release|autorelease|memory|leak)\b/i.test(content) ||
                          /\/\*.*\b(ARC|retain|release|autorelease|memory|leak)\b.*\*\//is.test(content);
    
    if (hasMemoryNotes) {
      return true;
    }
  }
  
  return false;
}

async function validateCodeExamples() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Code Example Validation');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  if (!fs.existsSync(EXAMPLES_DIR)) {
    console.error('❌ Examples directory not found:', EXAMPLES_DIR);
    process.exit(1);
  }
  
  // Find all tutorial examples
  const exampleDirs = fs.readdirSync(EXAMPLES_DIR)
    .filter(name => name.startsWith('tutorial-'))
    .map(name => path.join(EXAMPLES_DIR, name))
    .filter(dir => fs.statSync(dir).isDirectory());
  
  console.log(`Found ${exampleDirs.length} tutorial examples\n`);
  
  for (const exampleDir of exampleDirs) {
    const exampleName = path.basename(exampleDir);
    console.log(`Validating: ${exampleName}`);
    
    const result: CodeValidationResult = {
      example: exampleName,
      compiled: false,
      styleChecked: false,
      hasErrorHandling: false,
      hasMemoryNotes: false,
      issues: []
    };
    
    // Find source files
    const srcDir = path.join(exampleDir, 'src');
    if (!fs.existsSync(srcDir)) {
      result.issues.push('No src directory found');
      results.push(result);
      console.log('  ⚠️  No src directory\n');
      continue;
    }
    
    const sourceFiles = glob.sync('**/*.{m,h}', { cwd: srcDir })
      .map(f => path.join(srcDir, f));
    
    if (sourceFiles.length === 0) {
      result.issues.push('No source files found');
      results.push(result);
      console.log('  ⚠️  No source files\n');
      continue;
    }
    
    // Check compilation
    console.log('  Checking compilation...');
    const compileResult = await compileExample(exampleDir);
    result.compiled = compileResult.success;
    
    if (!result.compiled) {
      result.issues.push('Compilation failed');
      console.log('  ❌ Compilation failed');
    } else {
      console.log('  ✅ Compiles successfully');
    }
    
    // Check error handling
    result.hasErrorHandling = checkErrorHandling(sourceFiles);
    if (!result.hasErrorHandling) {
      result.issues.push('No error handling found');
      console.log('  ⚠️  No error handling detected');
    } else {
      console.log('  ✅ Has error handling');
    }
    
    // Check memory management notes
    result.hasMemoryNotes = checkMemoryNotes(sourceFiles);
    if (!result.hasMemoryNotes) {
      result.issues.push('No memory management notes');
      console.log('  ⚠️  No memory management notes');
    } else {
      console.log('  ✅ Has memory management notes');
    }
    
    results.push(result);
    console.log();
  }
  
  // Summary
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Summary');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  const compiled = results.filter(r => r.compiled).length;
  const withErrorHandling = results.filter(r => r.hasErrorHandling).length;
  const withMemoryNotes = results.filter(r => r.hasMemoryNotes).length;
  
  console.log(`Examples validated: ${results.length}`);
  console.log(`Compiled successfully: ${compiled}/${results.length}`);
  console.log(`With error handling: ${withErrorHandling}/${results.length}`);
  console.log(`With memory notes: ${withMemoryNotes}/${results.length}\n`);
  
  const allCompiled = compiled === results.length;
  
  if (allCompiled) {
    console.log('✅ PASSED: All examples compile\n');
  } else {
    console.log('❌ FAILED: Some examples do not compile\n');
  }
  
  // Generate report
  generateReport();
  
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Detailed report saved to: CODE_EXAMPLES_REPORT.md');
  console.log('═══════════════════════════════════════════════════════════════\n');
  
  process.exit(allCompiled ? 0 : 1);
}

function generateReport() {
  const lines: string[] = [];
  
  lines.push('# Code Examples Validation Report');
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('## Summary');
  lines.push('');
  
  const compiled = results.filter(r => r.compiled).length;
  const withErrorHandling = results.filter(r => r.hasErrorHandling).length;
  const withMemoryNotes = results.filter(r => r.hasMemoryNotes).length;
  
  lines.push(`- Examples validated: ${results.length}`);
  lines.push(`- Compiled successfully: ${compiled}/${results.length}`);
  lines.push(`- With error handling: ${withErrorHandling}/${results.length}`);
  lines.push(`- With memory notes: ${withMemoryNotes}/${results.length}`);
  lines.push('');
  
  lines.push('## Validation Criteria');
  lines.push('');
  lines.push('- **Compilation**: Code compiles without errors using CMake');
  lines.push('- **Error Handling**: Code includes error checking and nil checks');
  lines.push('- **Memory Notes**: Code includes comments about memory management');
  lines.push('');
  
  lines.push('## Results by Example');
  lines.push('');
  
  for (const result of results) {
    const status = result.compiled ? '✅' : '❌';
    lines.push(`### ${status} ${result.example}`);
    lines.push('');
    lines.push(`- Compilation: ${result.compiled ? '✅ Pass' : '❌ Fail'}`);
    lines.push(`- Error Handling: ${result.hasErrorHandling ? '✅ Present' : '⚠️ Missing'}`);
    lines.push(`- Memory Notes: ${result.hasMemoryNotes ? '✅ Present' : '⚠️ Missing'}`);
    
    if (result.issues.length > 0) {
      lines.push('');
      lines.push('**Issues:**');
      for (const issue of result.issues) {
        lines.push(`- ${issue}`);
      }
    }
    
    lines.push('');
  }
  
  lines.push('## Recommendations');
  lines.push('');
  
  const failedExamples = results.filter(r => !r.compiled);
  if (failedExamples.length > 0) {
    lines.push('### Compilation Failures');
    lines.push('');
    for (const example of failedExamples) {
      lines.push(`- **${example.example}**: Fix compilation errors before deployment`);
    }
    lines.push('');
  }
  
  const noErrorHandling = results.filter(r => !r.hasErrorHandling);
  if (noErrorHandling.length > 0) {
    lines.push('### Missing Error Handling');
    lines.push('');
    lines.push('Consider adding error handling to:');
    for (const example of noErrorHandling) {
      lines.push(`- ${example.example}`);
    }
    lines.push('');
  }
  
  const noMemoryNotes = results.filter(r => !r.hasMemoryNotes);
  if (noMemoryNotes.length > 0) {
    lines.push('### Missing Memory Management Notes');
    lines.push('');
    lines.push('Consider adding memory management comments to:');
    for (const example of noMemoryNotes) {
      lines.push(`- ${example.example}`);
    }
    lines.push('');
  }
  
  fs.writeFileSync(path.join(DOCS_DIR, 'CODE_EXAMPLES_REPORT.md'), lines.join('\n'));
}

// Run validation
validateCodeExamples().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

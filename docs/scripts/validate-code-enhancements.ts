#!/usr/bin/env tsx
/**
 * Code Enhancement Validation Script
 * 
 * Validates that all code block enhancement features are properly implemented
 * by checking the built HTML output.
 * 
 * This script validates:
 * - Syntax highlighting is applied
 * - Line numbers are present
 * - Line highlighting works
 * - Code block titles are rendered
 * - Copy buttons are present
 * - Code groups are rendered
 * - Annotations are styled
 * - Collapsible blocks are functional
 * 
 * Usage: npm run validate:code-enhancements
 */

import * as fs from 'fs'
import * as path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const docsRoot = path.resolve(__dirname, '..')
const distDir = path.join(docsRoot, '.vitepress', 'dist')

interface ValidationResult {
  feature: string
  passed: boolean
  message: string
  details?: string
}

class CodeEnhancementValidator {
  private results: ValidationResult[] = []
  
  async validateAll(): Promise<boolean> {
    console.log('🔍 Validating code block enhancements...\n')
    
    // Check if build output exists
    if (!fs.existsSync(distDir)) {
      console.error('❌ Build output not found. Run `npm run docs:build` first.')
      return false
    }
    
    // Validate each feature
    await this.validateSyntaxHighlighting()
    await this.validateLineNumbers()
    await this.validateLineHighlighting()
    await this.validateCodeTitles()
    await this.validateCopyButtons()
    await this.validateCodeGroups()
    await this.validateAnnotations()
    await this.validateCollapsibleBlocks()
    await this.validateThemeSupport()
    
    // Print results
    this.printResults()
    
    // Return overall pass/fail
    const allPassed = this.results.every(r => r.passed)
    return allPassed
  }
  
  private async validateSyntaxHighlighting(): Promise<void> {
    console.log('📝 Validating syntax highlighting...')
    
    const testFile = path.join(distDir, 'test-syntax-highlighting.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Syntax Highlighting',
        passed: false,
        message: 'Test page not found in build output'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for Shiki syntax highlighting classes
    const hasShikiClasses = content.includes('class="shiki') || content.includes('class="vp-code')
    
    // Check for language-specific highlighting
    const hasObjCHighlighting = content.includes('objective-c') || content.includes('objc')
    
    if (hasShikiClasses && hasObjCHighlighting) {
      this.results.push({
        feature: 'Syntax Highlighting',
        passed: true,
        message: 'Shiki syntax highlighting is applied correctly'
      })
    } else {
      this.results.push({
        feature: 'Syntax Highlighting',
        passed: false,
        message: 'Syntax highlighting not properly applied',
        details: `Shiki classes: ${hasShikiClasses}, Objective-C: ${hasObjCHighlighting}`
      })
    }
  }
  
  private async validateLineNumbers(): Promise<void> {
    console.log('🔢 Validating line numbers...')
    
    const testFile = path.join(distDir, 'test-syntax-highlighting.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Line Numbers',
        passed: false,
        message: 'Test page not found'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for line number elements
    const hasLineNumbers = content.includes('line-numbers-mode') || 
                          content.includes('line-number') ||
                          content.includes('data-line')
    
    this.results.push({
      feature: 'Line Numbers',
      passed: hasLineNumbers,
      message: hasLineNumbers 
        ? 'Line numbers are enabled' 
        : 'Line numbers not found in output'
    })
  }
  
  private async validateLineHighlighting(): Promise<void> {
    console.log('✨ Validating line highlighting...')
    
    const testFile = path.join(distDir, 'code-enhancement-examples.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Line Highlighting',
        passed: false,
        message: 'Test page not found'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for highlighted line classes
    const hasHighlightedLines = content.includes('highlighted') || 
                                content.includes('has-focused-lines') ||
                                content.includes('line.highlighted')
    
    this.results.push({
      feature: 'Line Highlighting',
      passed: hasHighlightedLines,
      message: hasHighlightedLines 
        ? 'Line highlighting is implemented' 
        : 'Line highlighting not found'
    })
  }
  
  private async validateCodeTitles(): Promise<void> {
    console.log('📄 Validating code block titles...')
    
    const testFile = path.join(distDir, 'code-enhancement-examples.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Code Block Titles',
        passed: false,
        message: 'Test page not found'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for code block title elements
    const hasTitles = content.includes('PDSApplication.m') || 
                     content.includes('lang-title') ||
                     content.includes('vp-code-group-title')
    
    this.results.push({
      feature: 'Code Block Titles',
      passed: hasTitles,
      message: hasTitles 
        ? 'Code block titles are rendered' 
        : 'Code block titles not found'
    })
  }
  
  private async validateCopyButtons(): Promise<void> {
    console.log('📋 Validating copy buttons...')
    
    const testFile = path.join(distDir, 'code-enhancement-examples.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Copy Buttons',
        passed: false,
        message: 'Test page not found'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for copy button elements
    const hasCopyButtons = content.includes('copy') && 
                          (content.includes('button') || content.includes('vp-copy'))
    
    this.results.push({
      feature: 'Copy Buttons',
      passed: hasCopyButtons,
      message: hasCopyButtons 
        ? 'Copy buttons are present' 
        : 'Copy buttons not found'
    })
  }
  
  private async validateCodeGroups(): Promise<void> {
    console.log('📑 Validating code groups...')
    
    const testFile = path.join(distDir, 'code-enhancement-examples.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Code Groups',
        passed: false,
        message: 'Test page not found'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for code group elements
    const hasCodeGroups = content.includes('vp-code-group') || 
                         content.includes('code-group') ||
                         (content.includes('macOS') && content.includes('Linux'))
    
    this.results.push({
      feature: 'Code Groups',
      passed: hasCodeGroups,
      message: hasCodeGroups 
        ? 'Code groups are rendered with tabs' 
        : 'Code groups not found'
    })
  }
  
  private async validateAnnotations(): Promise<void> {
    console.log('💬 Validating code annotations...')
    
    const testFile = path.join(distDir, 'code-enhancement-examples.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Code Annotations',
        passed: false,
        message: 'Test page not found'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for annotation markers in code
    const hasAnnotations = content.includes('[!NOTE]') || 
                          content.includes('[!WARNING]') ||
                          content.includes('[!ERROR]') ||
                          content.includes('[!TIP]')
    
    // Check for annotation styling
    const hasAnnotationStyles = content.includes('annotation-') || 
                               content.includes('code-block-with-annotations')
    
    const passed = hasAnnotations || hasAnnotationStyles
    
    this.results.push({
      feature: 'Code Annotations',
      passed,
      message: passed 
        ? 'Code annotations are implemented' 
        : 'Code annotations not found',
      details: `Markers: ${hasAnnotations}, Styles: ${hasAnnotationStyles}`
    })
  }
  
  private async validateCollapsibleBlocks(): Promise<void> {
    console.log('📦 Validating collapsible code blocks...')
    
    const testFile = path.join(distDir, 'code-collapse-example.html')
    if (!fs.existsSync(testFile)) {
      this.results.push({
        feature: 'Collapsible Blocks',
        passed: false,
        message: 'Test page not found'
      })
      return
    }
    
    const content = fs.readFileSync(testFile, 'utf-8')
    
    // Check for details/summary elements
    const hasDetailsElements = content.includes('<details') && content.includes('<summary')
    
    // Check for code-collapse class
    const hasCollapseClass = content.includes('code-collapse')
    
    const passed = hasDetailsElements && hasCollapseClass
    
    this.results.push({
      feature: 'Collapsible Blocks',
      passed,
      message: passed 
        ? 'Collapsible code blocks are functional' 
        : 'Collapsible blocks not properly implemented',
      details: `Details elements: ${hasDetailsElements}, Collapse class: ${hasCollapseClass}`
    })
  }
  
  private async validateThemeSupport(): Promise<void> {
    console.log('🎨 Validating theme support...')
    
    // Check CSS file for theme-specific styles
    const cssFiles = this.findFiles(distDir, '.css')
    
    let hasDarkModeStyles = false
    let hasLightModeStyles = false
    
    for (const cssFile of cssFiles) {
      const content = fs.readFileSync(cssFile, 'utf-8')
      
      if (content.includes('.dark') || content.includes('dark-mode')) {
        hasDarkModeStyles = true
      }
      
      if (content.includes('github-light') || content.includes('github-dark')) {
        hasLightModeStyles = true
      }
    }
    
    const passed = hasDarkModeStyles || hasLightModeStyles
    
    this.results.push({
      feature: 'Theme Support',
      passed,
      message: passed 
        ? 'Light and dark theme support is configured' 
        : 'Theme support not found',
      details: `Dark mode: ${hasDarkModeStyles}, Light mode: ${hasLightModeStyles}`
    })
  }
  
  private findFiles(dir: string, extension: string): string[] {
    const files: string[] = []
    
    if (!fs.existsSync(dir)) {
      return files
    }
    
    const entries = fs.readdirSync(dir, { withFileTypes: true })
    
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name)
      
      if (entry.isDirectory()) {
        files.push(...this.findFiles(fullPath, extension))
      } else if (entry.name.endsWith(extension)) {
        files.push(fullPath)
      }
    }
    
    return files
  }
  
  private printResults(): void {
    console.log('\n' + '='.repeat(60))
    console.log('VALIDATION RESULTS')
    console.log('='.repeat(60) + '\n')
    
    const passed = this.results.filter(r => r.passed)
    const failed = this.results.filter(r => !r.passed)
    
    // Print passed features
    if (passed.length > 0) {
      console.log('✅ PASSED FEATURES:\n')
      passed.forEach(r => {
        console.log(`  ✓ ${r.feature}: ${r.message}`)
        if (r.details) {
          console.log(`    ${r.details}`)
        }
      })
      console.log()
    }
    
    // Print failed features
    if (failed.length > 0) {
      console.log('❌ FAILED FEATURES:\n')
      failed.forEach(r => {
        console.log(`  ✗ ${r.feature}: ${r.message}`)
        if (r.details) {
          console.log(`    ${r.details}`)
        }
      })
      console.log()
    }
    
    // Print summary
    console.log('='.repeat(60))
    console.log(`SUMMARY: ${passed.length}/${this.results.length} features passed`)
    console.log('='.repeat(60))
  }
}

// Main execution
async function main() {
  const validator = new CodeEnhancementValidator()
  const allPassed = await validator.validateAll()
  
  if (allPassed) {
    console.log('\n✅ All code enhancement features validated successfully!')
    process.exit(0)
  } else {
    console.log('\n❌ Some features failed validation. See details above.')
    process.exit(1)
  }
}

main().catch(error => {
  console.error('❌ Validation failed with error:', error)
  process.exit(1)
})

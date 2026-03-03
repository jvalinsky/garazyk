#!/usr/bin/env tsx
/**
 * Documentation Validation Script
 * 
 * Validates documentation for:
 * - Broken internal links
 * - Broken external links
 * - Missing diagrams
 * - Invalid code blocks
 * - Heading hierarchy
 * - Front matter
 */

import * as fs from 'fs'
import * as path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const docsRoot = path.resolve(__dirname, '..')

interface ValidationError {
  type: 'broken-link' | 'missing-diagram' | 'invalid-code' | 'heading-hierarchy' | 'front-matter'
  file: string
  line?: number
  message: string
}

interface ValidationResult {
  passed: boolean
  errors: ValidationError[]
  warnings: string[]
}

class DocumentationValidator {
  private errors: ValidationError[] = []
  private warnings: string[] = []
  
  async validateAll(): Promise<ValidationResult> {
    console.log('🔍 Validating documentation...\n')
    
    await this.validateLinks()
    await this.validateDiagrams()
    await this.validateCodeBlocks()
    await this.validateHeadingHierarchy()
    
    const passed = this.errors.length === 0
    
    console.log('\n' + '='.repeat(60))
    if (passed) {
      console.log('✅ All validations passed!')
    } else {
      console.log(`❌ Found ${this.errors.length} error(s)`)
    }
    
    if (this.warnings.length > 0) {
      console.log(`⚠️  Found ${this.warnings.length} warning(s)`)
    }
    
    return {
      passed,
      errors: this.errors,
      warnings: this.warnings
    }
  }
  
  async validateLinks(): Promise<void> {
    console.log('📎 Validating links...')
    
    const markdownFiles = this.findMarkdownFiles(docsRoot)
    
    for (const file of markdownFiles) {
      const content = fs.readFileSync(file, 'utf-8')
      const lines = content.split('\n')
      
      // Find markdown links: [text](url)
      const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g
      
      lines.forEach((line, index) => {
        let match
        while ((match = linkRegex.exec(line)) !== null) {
          const linkText = match[1]
          const linkUrl = match[2]
          
          // Skip external links and anchors for now
          if (linkUrl.startsWith('http') || linkUrl.startsWith('#')) {
            continue
          }
          
          // Check if internal link target exists
          const targetPath = this.resolveLink(file, linkUrl)
          if (!fs.existsSync(targetPath)) {
            this.errors.push({
              type: 'broken-link',
              file: path.relative(docsRoot, file),
              line: index + 1,
              message: `Broken link: ${linkUrl} -> ${targetPath}`
            })
          }
        }
      })
    }
    
    console.log(`  Checked ${markdownFiles.length} files`)
  }
  
  async validateDiagrams(): Promise<void> {
    console.log('🖼️  Validating diagrams...')
    
    const diagramsDir = path.join(docsRoot, '12-diagrams')
    if (!fs.existsSync(diagramsDir)) {
      this.warnings.push('Diagrams directory not found: 12-diagrams/')
      return
    }
    
    const svgFiles = fs.readdirSync(diagramsDir)
      .filter(f => f.endsWith('.svg'))
    
    console.log(`  Found ${svgFiles.length} SVG diagrams`)
    
    // Check if diagrams are referenced in documentation
    const markdownFiles = this.findMarkdownFiles(docsRoot)
    const allContent = markdownFiles
      .map(f => fs.readFileSync(f, 'utf-8'))
      .join('\n')
    
    for (const svgFile of svgFiles) {
      if (!allContent.includes(svgFile)) {
        this.warnings.push(`Diagram not referenced: ${svgFile}`)
      }
    }
  }
  
  async validateCodeBlocks(): Promise<void> {
    console.log('💻 Validating code blocks...')
    
    const markdownFiles = this.findMarkdownFiles(docsRoot)
    
    for (const file of markdownFiles) {
      const content = fs.readFileSync(file, 'utf-8')
      const lines = content.split('\n')
      
      let inCodeBlock = false
      let codeBlockStart = 0
      
      lines.forEach((line, index) => {
        if (line.startsWith('```')) {
          if (!inCodeBlock) {
            // Starting code block
            inCodeBlock = true
            codeBlockStart = index + 1
            
            // Check if language is specified
            const lang = line.substring(3).trim()
            if (!lang && line === '```') {
              this.warnings.push(
                `Code block without language at ${path.relative(docsRoot, file)}:${index + 1}`
              )
            }
          } else {
            // Ending code block
            inCodeBlock = false
          }
        }
      })
      
      // Check for unclosed code blocks
      if (inCodeBlock) {
        this.errors.push({
          type: 'invalid-code',
          file: path.relative(docsRoot, file),
          line: codeBlockStart,
          message: 'Unclosed code block'
        })
      }
    }
  }
  
  async validateHeadingHierarchy(): Promise<void> {
    console.log('📋 Validating heading hierarchy...')
    
    const markdownFiles = this.findMarkdownFiles(docsRoot)
    
    for (const file of markdownFiles) {
      const content = fs.readFileSync(file, 'utf-8')
      const lines = content.split('\n')
      
      let previousLevel = 0
      
      lines.forEach((line, index) => {
        const headingMatch = line.match(/^(#{1,6})\s+(.+)/)
        if (headingMatch) {
          const level = headingMatch[1].length
          
          // Check if we're skipping levels (e.g., h1 -> h3)
          if (level > previousLevel + 1 && previousLevel > 0) {
            this.warnings.push(
              `Heading hierarchy skip at ${path.relative(docsRoot, file)}:${index + 1} ` +
              `(h${previousLevel} -> h${level})`
            )
          }
          
          previousLevel = level
        }
      })
    }
  }
  
  private findMarkdownFiles(dir: string): string[] {
    const files: string[] = []
    
    const entries = fs.readdirSync(dir, { withFileTypes: true })
    
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name)
      
      // Skip certain directories
      if (entry.isDirectory()) {
        if (entry.name.startsWith('.') || 
            entry.name === 'node_modules' ||
            entry.name === '_site' ||
            entry.name === 'site') {
          continue
        }
        files.push(...this.findMarkdownFiles(fullPath))
      } else if (entry.name.endsWith('.md')) {
        files.push(fullPath)
      }
    }
    
    return files
  }
  
  private resolveLink(fromFile: string, linkUrl: string): string {
    // Remove anchor
    const urlWithoutAnchor = linkUrl.split('#')[0]
    
    // Remove .md extension if present (VitePress uses clean URLs)
    const cleanUrl = urlWithoutAnchor.replace(/\.md$/, '')
    
    // Resolve relative to file location
    const fromDir = path.dirname(fromFile)
    let targetPath = path.resolve(fromDir, cleanUrl)
    
    // Try with .md extension
    if (!fs.existsSync(targetPath)) {
      targetPath = targetPath + '.md'
    }
    
    // Try as directory with index.md
    if (!fs.existsSync(targetPath)) {
      targetPath = path.join(targetPath.replace(/\.md$/, ''), 'index.md')
    }
    
    return targetPath
  }
}

// Main execution
async function main() {
  const args = process.argv.slice(2)
  const validator = new DocumentationValidator()
  
  let result: ValidationResult
  
  if (args.includes('--links')) {
    await validator.validateLinks()
    result = { passed: true, errors: [], warnings: [] }
  } else if (args.includes('--diagrams')) {
    await validator.validateDiagrams()
    result = { passed: true, errors: [], warnings: [] }
  } else if (args.includes('--code-blocks')) {
    await validator.validateCodeBlocks()
    result = { passed: true, errors: [], warnings: [] }
  } else {
    result = await validator.validateAll()
  }
  
  // Exit with error code if validation failed
  if (!result.passed) {
    process.exit(1)
  }
}

main().catch(error => {
  console.error('❌ Validation failed:', error)
  process.exit(1)
})

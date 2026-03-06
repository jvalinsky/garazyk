#!/usr/bin/env tsx
/**
 * Documentation validation for the canonical VitePress contributor docs.
 *
 * Validates:
 * - broken internal links
 * - missing diagram references
 * - malformed code fences
 * - heading hierarchy
 * - tutorial structure and duplicate required sections
 * - oversized non-appendix tutorial code blocks
 * - stale CLI command names in examples
 * - unsupported config keys in examples
 */

import * as fs from 'fs'
import * as path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const docsRoot = path.resolve(__dirname, '..')

type ValidationType =
  | 'broken-link'
  | 'missing-diagram'
  | 'invalid-code'
  | 'heading-hierarchy'
  | 'tutorial-structure'
  | 'oversized-code-block'
  | 'stale-cli-command'
  | 'unsupported-config-key'

interface ValidationError {
  type: ValidationType
  file: string
  line?: number
  message: string
}

interface ValidationResult {
  passed: boolean
  errors: ValidationError[]
  warnings: string[]
}

interface CodeBlock {
  lang: string
  content: string
  startLine: number
  endLine: number
  inAppendix: boolean
}

interface MarkdownAnalysis {
  codeBlocks: CodeBlock[]
  unclosedCodeBlockStartLine?: number
}

interface ContentPatternRule {
  regex: RegExp
  message: string
}

const SHELL_LANGS = new Set(['bash', 'sh', 'shell', 'zsh', 'console'])
const CONFIG_LANGS = new Set(['json', 'yaml', 'yml', 'toml', 'ini'])

const TUTORIAL_SECTION_RULES = [
  {
    name: 'Overview',
    regex: /^##\s+Overview\s*$/gim,
  },
  {
    name: 'Learning Objectives',
    regex: /^\*\*Learning Objectives:\*\*/gim,
  },
  {
    name: 'Estimated Time',
    regex: /^\*\*Estimated Time:\*\*/gim,
  },
  {
    name: 'Prerequisites',
    regex: /^##\s+Prerequisites\s*$/gim,
  },
  {
    name: 'Troubleshooting',
    regex: /^##\s+Troubleshooting\s*$/gim,
  },
  {
    name: 'Next Steps',
    regex: /^##\s+Next Steps\s*$/gim,
  },
  {
    name: 'Summary',
    regex: /^##\s+Summary\s*$/gim,
  },
]

const CONFIG_BLOCK_PATTERNS: ContentPatternRule[] = [
  {
    regex: /\binviteCodeRequired\b/,
    message:
      'Unsupported camelCase config key in example. Use session.invite_code_required.',
  },
  {
    regex: /\brateLimit\b/,
    message: 'Unsupported config root in example. Use rate_limit.',
  },
  {
    regex: /\bappViewURL\b/,
    message: 'Unsupported config key in example. Use appview.url.',
  },
  {
    regex: /\bappViewDID\b/,
    message: 'Unsupported config key in example. Use appview.did.',
  },
  {
    regex: /\blocalAppViewEnabled\b/,
    message: 'Unsupported config key in example. Use appview.local_enabled.',
  },
  {
    regex: /"debug"\s*:\s*\{[\s\S]*?"verbose"\s*:/i,
    message: 'Unsupported debug key in example. Use debug.verbose_logging.',
  },
  {
    regex: /"debug"\s*:\s*\{[\s\S]*?"logLevel"\s*:/i,
    message: 'Unsupported debug key in example. Use logging.level.',
  },
]

const CLI_BLOCK_PATTERNS: ContentPatternRule[] = [
  {
    regex: /\b(?:\.\/build\/bin\/kaszlak|pds)\s+server\b/,
    message: 'Stale CLI command in example. Use "serve", not "server".',
  },
  {
    regex: /\b(?:\.\/build\/bin\/kaszlak|pds)\s+database\b/,
    message:
      'Stale CLI command in example. There is no top-level "database" command.',
  },
]

class DocumentationValidator {
  private errors: ValidationError[] = []
  private warnings: string[] = []

  async validateAll(): Promise<ValidationResult> {
    console.log('Validating documentation...\n')

    await this.validateLinks()
    await this.validateDiagrams()
    await this.validateCodeBlocks()
    await this.validateHeadingHierarchy()
    await this.validateTutorialStructure()
    await this.validateCanonicalExamples()

    return this.snapshot(true)
  }

  async validateLinks(): Promise<void> {
    console.log('Validating links...')

    const markdownFiles = this.findMarkdownFiles(docsRoot).filter(file =>
      this.isCanonicalSiteDoc(file)
    )

    for (const file of markdownFiles) {
      const content = fs.readFileSync(file, 'utf-8')
      const lines = content.split('\n')

      lines.forEach((line, index) => {
        const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g
        let match: RegExpExecArray | null

        while ((match = linkRegex.exec(line)) !== null) {
          const linkUrl = match[2].trim()

          if (
            linkUrl.startsWith('#') ||
            /^(?:https?:|mailto:|tel:)/.test(linkUrl)
          ) {
            continue
          }

          const targetPath = this.resolveLink(file, linkUrl)
          if (!fs.existsSync(targetPath)) {
            this.errors.push({
              type: 'broken-link',
              file: this.relativePath(file),
              line: index + 1,
              message: `Broken link: ${linkUrl}`,
            })
          }
        }
      })
    }

    console.log(`  Checked ${markdownFiles.length} files`)
  }

  async validateDiagrams(): Promise<void> {
    console.log('Validating diagrams...')

    const diagramsDir = path.join(docsRoot, '12-diagrams')
    if (!fs.existsSync(diagramsDir)) {
      this.warnings.push('Diagrams directory not found: 12-diagrams/')
      return
    }

    const svgFiles = fs
      .readdirSync(diagramsDir)
      .filter(file => file.endsWith('.svg'))

    const markdownFiles = this.findMarkdownFiles(docsRoot).filter(file =>
      this.isCanonicalSiteDoc(file)
    )
    const allContent = markdownFiles
      .map(file => fs.readFileSync(file, 'utf-8'))
      .join('\n')

    for (const svgFile of svgFiles) {
      if (!allContent.includes(svgFile)) {
        this.warnings.push(`Diagram not referenced: ${svgFile}`)
      }
    }

    console.log(`  Found ${svgFiles.length} SVG diagrams`)
  }

  async validateCodeBlocks(): Promise<void> {
    console.log('Validating code blocks...')

    const markdownFiles = this.findMarkdownFiles(docsRoot).filter(file =>
      this.isCanonicalSiteDoc(file)
    )

    for (const file of markdownFiles) {
      const content = fs.readFileSync(file, 'utf-8')
      const analysis = this.analyzeMarkdown(content)

      if (analysis.unclosedCodeBlockStartLine) {
        this.errors.push({
          type: 'invalid-code',
          file: this.relativePath(file),
          line: analysis.unclosedCodeBlockStartLine,
          message: 'Unclosed code block',
        })
      }

      for (const block of analysis.codeBlocks) {
        if (!block.lang) {
          this.warnings.push(
            `Code block without language at ${this.relativePath(file)}:${block.startLine}`
          )
        }

        if (!this.isTutorial(file) || block.inAppendix) {
          continue
        }

        const lineCount = this.codeBlockLineCount(block)
        if (SHELL_LANGS.has(block.lang) && lineCount > 10) {
          this.errors.push({
            type: 'oversized-code-block',
            file: this.relativePath(file),
            line: block.startLine,
            message:
              'Shell block exceeds 10 lines outside Appendix in tutorial.',
          })
          continue
        }

        if (lineCount > 20) {
          this.errors.push({
            type: 'oversized-code-block',
            file: this.relativePath(file),
            line: block.startLine,
            message:
              'Code block exceeds 20 lines outside Appendix in tutorial.',
          })
        }
      }
    }

    console.log(`  Checked ${markdownFiles.length} files`)
  }

  async validateHeadingHierarchy(): Promise<void> {
    console.log('Validating heading hierarchy...')

    const markdownFiles = this.findMarkdownFiles(docsRoot).filter(file =>
      this.isCanonicalSiteDoc(file)
    )

    for (const file of markdownFiles) {
      const content = fs.readFileSync(file, 'utf-8')
      const lines = content.split('\n')
      let previousLevel = 0

      lines.forEach((line, index) => {
        const headingMatch = line.match(/^(#{1,6})\s+(.+)/)
        if (!headingMatch) {
          return
        }

        const level = headingMatch[1].length
        if (level > previousLevel + 1 && previousLevel > 0) {
          this.warnings.push(
            `Heading hierarchy skip at ${this.relativePath(file)}:${index + 1} ` +
              `(h${previousLevel} -> h${level})`
          )
        }

        previousLevel = level
      })
    }

    console.log(`  Checked ${markdownFiles.length} files`)
  }

  async validateTutorialStructure(): Promise<void> {
    console.log('Validating tutorial structure...')

    const tutorialDir = path.join(docsRoot, '10-tutorials')
    const tutorialFiles = this.findMarkdownFiles(tutorialDir).filter(file =>
      path.basename(file).startsWith('tutorial-')
    )

    for (const file of tutorialFiles) {
      const content = fs.readFileSync(file, 'utf-8')

      for (const rule of TUTORIAL_SECTION_RULES) {
        const count = this.countMatches(content, rule.regex)

        if (count === 0) {
          this.errors.push({
            type: 'tutorial-structure',
            file: this.relativePath(file),
            message: `Missing required tutorial section: ${rule.name}`,
          })
        } else if (count > 1) {
          this.errors.push({
            type: 'tutorial-structure',
            file: this.relativePath(file),
            message: `Duplicate required tutorial section: ${rule.name}`,
          })
        }
      }
    }

    console.log(`  Checked ${tutorialFiles.length} tutorials`)
  }

  async validateCanonicalExamples(): Promise<void> {
    console.log('Validating canonical docs examples...')

    const canonicalFiles = this.findMarkdownFiles(docsRoot).filter(file =>
      this.isCanonicalSiteDoc(file)
    )

    for (const file of canonicalFiles) {
      const content = fs.readFileSync(file, 'utf-8')
      const analysis = this.analyzeMarkdown(content)

      for (const block of analysis.codeBlocks) {
        if (this.isConfigLikeBlock(block)) {
          this.checkBlockPatterns(
            file,
            block,
            CONFIG_BLOCK_PATTERNS,
            'unsupported-config-key'
          )
        }

        if (this.isShellLikeBlock(block)) {
          this.checkBlockPatterns(
            file,
            block,
            CLI_BLOCK_PATTERNS,
            'stale-cli-command'
          )
        }
      }
    }

    console.log(`  Checked ${canonicalFiles.length} canonical docs files`)
  }

  snapshot(printSummary = false): ValidationResult {
    const result = {
      passed: this.errors.length === 0,
      errors: [...this.errors],
      warnings: [...this.warnings],
    }

    if (printSummary) {
      console.log('\n' + '='.repeat(60))
      if (result.passed) {
        console.log('All validations passed')
      } else {
        console.log(`Found ${result.errors.length} error(s)`)
      }

      if (result.warnings.length > 0) {
        console.log(`Found ${result.warnings.length} warning(s)`)
      }
    }

    return result
  }

  private analyzeMarkdown(content: string): MarkdownAnalysis {
    const lines = content.split('\n')
    const codeBlocks: CodeBlock[] = []

    let inCodeBlock = false
    let codeBlockStart = 0
    let codeBlockLang = ''
    let codeLines: string[] = []
    let inAppendix = false

    lines.forEach((line, index) => {
      if (!inCodeBlock) {
        const headingMatch = line.match(/^(#{2,6})\s+(.+)/)
        if (headingMatch && headingMatch[1].length === 2) {
          inAppendix = /^appendix\b/i.test(headingMatch[2].trim())
        }
      }

      if (line.startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true
          codeBlockStart = index + 1
          codeBlockLang = line.slice(3).trim().toLowerCase()
          codeLines = []
        } else {
          codeBlocks.push({
            lang: codeBlockLang,
            content: codeLines.join('\n'),
            startLine: codeBlockStart,
            endLine: index + 1,
            inAppendix,
          })

          inCodeBlock = false
          codeBlockStart = 0
          codeBlockLang = ''
          codeLines = []
        }

        return
      }

      if (inCodeBlock) {
        codeLines.push(line)
      }
    })

    return {
      codeBlocks,
      unclosedCodeBlockStartLine: inCodeBlock ? codeBlockStart : undefined,
    }
  }

  private checkBlockPatterns(
    file: string,
    block: CodeBlock,
    rules: ContentPatternRule[],
    type: ValidationType
  ): void {
    for (const rule of rules) {
      const match = block.content.match(rule.regex)
      if (!match || match.index === undefined) {
        continue
      }

      const lineOffset = this.countNewlinesBefore(block.content, match.index)
      this.errors.push({
        type,
        file: this.relativePath(file),
        line: block.startLine + lineOffset,
        message: rule.message,
      })
    }
  }

  private countMatches(content: string, regex: RegExp): number {
    const matches = content.match(regex)
    return matches ? matches.length : 0
  }

  private countNewlinesBefore(content: string, index: number): number {
    let count = 0
    for (let i = 0; i < index; i++) {
      if (content[i] === '\n') {
        count += 1
      }
    }
    return count
  }

  private codeBlockLineCount(block: CodeBlock): number {
    if (block.content.length === 0) {
      return 0
    }
    return block.content.split('\n').length
  }

  private isShellLikeBlock(block: CodeBlock): boolean {
    if (SHELL_LANGS.has(block.lang)) {
      return true
    }

    return /\b(?:curl|kaszlak|pds|xcodebuild|xcodegen|docker)\b/.test(
      block.content
    )
  }

  private isConfigLikeBlock(block: CodeBlock): boolean {
    if (CONFIG_LANGS.has(block.lang)) {
      return true
    }

    return (
      block.lang.length === 0 &&
      /"(?:server|plc|session|logging|debug|appview|rate_limit)"/.test(
        block.content
      )
    )
  }

  private isTutorial(file: string): boolean {
    const relative = this.relativePath(file)
    return /^10-tutorials\/tutorial-.*\.md$/.test(relative)
  }

  private isCanonicalSiteDoc(file: string): boolean {
    const relative = this.relativePath(file)
    return (
      /^(?:\d{2}-)/.test(relative) ||
      relative === 'index.md' ||
      relative === 'README.md' ||
      relative === 'SUMMARY.md'
    )
  }

  private findMarkdownFiles(dir: string): string[] {
    const files: string[] = []
    const entries = fs.readdirSync(dir, { withFileTypes: true })

    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name)

      if (entry.isDirectory()) {
        if (
          entry.name.startsWith('.') ||
          entry.name === 'node_modules' ||
          entry.name === '_site' ||
          entry.name === 'site'
        ) {
          continue
        }

        files.push(...this.findMarkdownFiles(fullPath))
      } else if (entry.name.endsWith('.md')) {
        files.push(fullPath)
      }
    }

    return files
  }

  private relativePath(file: string): string {
    return path.relative(docsRoot, file).replace(/\\/g, '/')
  }

  private resolveLink(fromFile: string, linkUrl: string): string {
    const withoutQuery = linkUrl.split('?')[0]
    const withoutAnchor = withoutQuery.split('#')[0]

    let targetPath = withoutAnchor
    if (targetPath.startsWith('/')) {
      targetPath = path.join(docsRoot, targetPath)
    } else {
      targetPath = path.resolve(path.dirname(fromFile), targetPath)
    }

    const candidates = [
      targetPath,
      `${targetPath}.md`,
      path.join(targetPath, 'index.md'),
    ]

    return candidates.find(candidate => fs.existsSync(candidate)) ?? candidates[0]
  }
}

async function main() {
  const args = process.argv.slice(2)
  const validator = new DocumentationValidator()

  let result: ValidationResult

  if (args.includes('--check-links') || args.includes('--links')) {
    console.log('Running link validation only...\n')
    await validator.validateLinks()
    result = validator.snapshot()
  } else if (args.includes('--check-diagrams') || args.includes('--diagrams')) {
    console.log('Running diagram validation only...\n')
    await validator.validateDiagrams()
    result = validator.snapshot()
  } else if (
    args.includes('--check-code-blocks') ||
    args.includes('--code-blocks')
  ) {
    console.log('Running code block validation only...\n')
    await validator.validateCodeBlocks()
    result = validator.snapshot()
  } else if (args.includes('--tutorials')) {
    console.log('Running tutorial validation only...\n')
    await validator.validateTutorialStructure()
    result = validator.snapshot()
  } else if (args.includes('--content')) {
    console.log('Running canonical content validation only...\n')
    await validator.validateCanonicalExamples()
    result = validator.snapshot()
  } else {
    result = await validator.validateAll()
  }

  if (result.errors.length > 0) {
    console.log('\nErrors:')
    result.errors.forEach(error => {
      console.log(`  ${error.file}:${error.line ?? '?'} - ${error.message}`)
    })
  }

  if (result.warnings.length > 0) {
    console.log('\nWarnings:')
    result.warnings.forEach(warning => {
      console.log(`  ${warning}`)
    })
  }

  if (!result.passed) {
    process.exit(1)
  }
}

main().catch(error => {
  console.error('Validation failed:', error)
  process.exit(1)
})

#!/usr/bin/env tsx
/**
 * Tutorial structure validation for prose-first contributor tutorials.
 *
 * Checks:
 * - required sections exist exactly once
 * - oversized code blocks do not appear outside Appendix sections
 */

import * as fs from 'fs'
import * as path from 'path'
import { fileURLToPath } from 'url'
import { glob } from 'glob'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const docsRoot = path.resolve(__dirname, '..')

const REQUIRED_SECTION_PATTERNS = [
  { name: 'Overview', regex: /^##\s+Overview\s*$/gim },
  { name: 'Learning Objectives', regex: /^\*\*Learning Objectives:\*\*/gim },
  { name: 'Estimated Time', regex: /^\*\*Estimated Time:\*\*/gim },
  { name: 'Prerequisites', regex: /^##\s+Prerequisites\s*$/gim },
  { name: 'Troubleshooting', regex: /^##\s+Troubleshooting\s*$/gim },
  { name: 'Next Steps', regex: /^##\s+Next Steps\s*$/gim },
  { name: 'Summary', regex: /^##\s+Summary\s*$/gim },
]

const SHELL_LANGS = new Set(['bash', 'sh', 'shell', 'zsh', 'console'])

interface CodeBlock {
  lang: string
  content: string
  startLine: number
  inAppendix: boolean
}

interface TutorialIssue {
  line?: number
  message: string
}

interface ValidationResult {
  passed: boolean
  tutorialsChecked: number
  failures: Array<{
    tutorial: string
    issues: TutorialIssue[]
  }>
}

function countMatches(content: string, regex: RegExp): number {
  const matches = content.match(regex)
  return matches ? matches.length : 0
}

function analyzeMarkdown(content: string): CodeBlock[] {
  const lines = content.split('\n')
  const blocks: CodeBlock[] = []

  let inCodeBlock = false
  let startLine = 0
  let lang = ''
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
        startLine = index + 1
        lang = line.slice(3).trim().toLowerCase()
        codeLines = []
      } else {
        blocks.push({
          lang,
          content: codeLines.join('\n'),
          startLine,
          inAppendix,
        })
        inCodeBlock = false
        startLine = 0
        lang = ''
        codeLines = []
      }
      return
    }

    if (inCodeBlock) {
      codeLines.push(line)
    }
  })

  return blocks
}

function validateTutorialContent(content: string): TutorialIssue[] {
  const issues: TutorialIssue[] = []

  for (const rule of REQUIRED_SECTION_PATTERNS) {
    const count = countMatches(content, rule.regex)
    if (count === 0) {
      issues.push({ message: `Missing required section: ${rule.name}` })
    } else if (count > 1) {
      issues.push({ message: `Duplicate required section: ${rule.name}` })
    }
  }

  const blocks = analyzeMarkdown(content)
  for (const block of blocks) {
    if (block.inAppendix) {
      continue
    }

    const lineCount =
      block.content.length === 0 ? 0 : block.content.split('\n').length

    if (SHELL_LANGS.has(block.lang) && lineCount > 10) {
      issues.push({
        line: block.startLine,
        message: 'Shell block exceeds 10 lines outside Appendix',
      })
      continue
    }

    if (lineCount > 20) {
      issues.push({
        line: block.startLine,
        message: 'Code block exceeds 20 lines outside Appendix',
      })
    }
  }

  return issues
}

async function validateTutorialStructure(): Promise<ValidationResult> {
  console.log('Validating tutorial structure\n')

  const tutorialFiles = (
    await glob(path.join(docsRoot, '10-tutorials', 'tutorial-*.md'))
  ).sort()

  if (tutorialFiles.length === 0) {
    throw new Error('No tutorial files found in 10-tutorials/')
  }

  const failures: ValidationResult['failures'] = []

  for (const file of tutorialFiles) {
    const content = fs.readFileSync(file, 'utf-8')
    const issues = validateTutorialContent(content)
    const relative = path.relative(docsRoot, file).replace(/\\/g, '/')

    if (issues.length === 0) {
      console.log(`  OK  ${relative}`)
      continue
    }

    failures.push({
      tutorial: relative,
      issues,
    })
    console.log(`  FAIL ${relative}`)
    issues.forEach(issue => {
      const lineSuffix = issue.line ? `:${issue.line}` : ''
      console.log(`       ${lineSuffix} ${issue.message}`)
    })
  }

  return {
    passed: failures.length === 0,
    tutorialsChecked: tutorialFiles.length,
    failures,
  }
}

async function main() {
  try {
    const result = await validateTutorialStructure()

    console.log('\n' + '='.repeat(60))
    console.log(`Tutorials checked: ${result.tutorialsChecked}`)
    console.log(`Failures: ${result.failures.length}`)

    if (!result.passed) {
      process.exit(1)
    }
  } catch (error) {
    console.error('Tutorial validation failed:', error)
    process.exit(1)
  }
}

main()

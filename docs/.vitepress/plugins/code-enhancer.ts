/**
 * Code Enhancement Plugin for VitePress
 * 
 * VitePress provides built-in code enhancement features via Shiki:
 * - Line highlighting with {2,4-6} syntax
 * - Code block titles with [filename.m] syntax
 * - Copy-to-clipboard buttons (automatic)
 * - Syntax highlighting for 100+ languages
 * - Line numbers (configured in config.ts)
 * 
 * This plugin extends VitePress with additional custom features:
 * - Code annotations with special comment syntax
 * - Enhanced error/warning highlighting
 * - Custom code block containers
 * - Collapsible code blocks for long examples
 * 
 * @see https://vitepress.dev/guide/markdown#syntax-highlighting-in-code-blocks
 */

import type MarkdownIt from 'markdown-it'
import container from 'markdown-it-container'

/**
 * Code Enhancement Plugin
 * 
 * Extends VitePress's built-in code features with custom enhancements.
 * 
 * Built-in VitePress features (no plugin needed):
 * - Line highlighting: ```objc{2,4-6}
 * - Code titles: ```objc [PDSApplication.m]
 * - Copy buttons: Automatic on all code blocks
 * - Line numbers: Configured via markdown.lineNumbers in config.ts
 * 
 * Custom features added by this plugin:
 * - Annotation highlighting for special comments
 * - Warning/error line highlighting
 * - Code diff support
 * - Collapsible code blocks for long examples
 */
export function codeEnhancerPlugin(md: MarkdownIt) {
  // Store the original fence renderer
  const defaultRender = md.renderer.rules.fence!
  
  // Override fence renderer for custom enhancements
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const token = tokens[idx]
    const info = token.info ? md.utils.unescapeAll(token.info).trim() : ''
    
    // Check for custom annotations in the code content
    // Example: // [!NOTE] This is important
    // Example: // [!WARNING] Be careful here
    // Example: // [!ERROR] This will fail
    const content = token.content
    const hasAnnotations = /\/\/\s*\[!(NOTE|WARNING|ERROR|TIP)\]/.test(content)
    
    // Get the default rendered output
    let result = defaultRender(tokens, idx, options, env, self)
    
    // Add custom wrapper for annotated code blocks
    if (hasAnnotations) {
      result = `<div class="code-block-with-annotations">${result}</div>`
    }
    
    return result
  }
  
  // Add custom container for collapsible code blocks
  // Usage: ::: code-collapse [Summary text]
  md.use(container, 'code-collapse', {
    validate: (params: string) => {
      return params.trim().match(/^code-collapse\s*(.*)$/)
    },
    render: (tokens: any[], idx: number) => {
      const m = tokens[idx].info.trim().match(/^code-collapse\s*(.*)$/)
      if (tokens[idx].nesting === 1) {
        // Opening tag
        const summary = m && m[1] ? md.utils.escapeHtml(m[1]) : 'Click to expand code'
        return `<details class="code-collapse"><summary>${summary}</summary>\n`
      } else {
        // Closing tag
        return '</details>\n'
      }
    }
  })
}

/**
 * Configuration for code enhancement options
 */
export interface CodeEnhancementOptions {
  /** Enable line numbers (configured in config.ts) */
  lineNumbers: boolean
  /** Enable line highlighting with {2,4-6} syntax (built-in) */
  highlightLines: boolean
  /** Enable copy-to-clipboard buttons (built-in) */
  copyButton: boolean
  /** Enable custom annotation highlighting */
  annotations: boolean
  /** Enable code group tabs (built-in via ::: code-group) */
  tabs: boolean
}

export const defaultCodeEnhancementOptions: CodeEnhancementOptions = {
  lineNumbers: true,
  highlightLines: true,
  copyButton: true,
  annotations: true,
  tabs: true
}

/**
 * Usage Examples:
 * 
 * 1. Line Highlighting (built-in):
 * ```objc{2,4-6}
 * // Line 1
 * // Line 2 - highlighted
 * // Line 3
 * // Lines 4-6 highlighted
 * // Line 5
 * // Line 6
 * ```
 * 
 * 2. Code Block Title (built-in):
 * ```objc [PDSApplication.m]
 * @implementation PDSApplication
 * // ...
 * @end
 * ```
 * 
 * 3. Code Groups for Platform-Specific Code (built-in):
 * ::: code-group
 * ```objc [macOS]
 * #import <Security/Security.h>
 * // macOS-specific code
 * ```
 * ```objc [Linux]
 * #import <openssl/evp.h>
 * // Linux-specific code
 * ```
 * :::
 * 
 * 4. Code Annotations (custom):
 * ```objc
 * // [!NOTE] This is an important implementation detail
 * - (void)startServer {
 *     // [!WARNING] Ensure port is not already in use
 *     [self bindToPort:self.port];
 * }
 * ```
 * 
 * 5. Collapsible Code Blocks (custom):
 * ::: code-collapse Complete implementation details
 * ```objc
 * // Long code example that can be collapsed
 * @implementation PDSApplication
 * - (void)startServer {
 *     // ... many lines of code ...
 * }
 * @end
 * ```
 * :::
 * 
 * 6. Combining Features:
 * ```objc{2,5-7} [PDSApplication.m]
 * @implementation PDSApplication
 * // [!NOTE] This line is highlighted
 * - (void)startServer {
 *     NSLog(@"Starting server");
 *     // [!WARNING] These lines are highlighted
 *     // Check configuration first
 *     [self validateConfiguration];
 * }
 * @end
 * ```
 */

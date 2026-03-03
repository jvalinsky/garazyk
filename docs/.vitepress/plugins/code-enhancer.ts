/**
 * Code Enhancement Plugin for VitePress
 * 
 * Provides enhanced code block features:
 * - Line highlighting
 * - Code block titles
 * - Copy-to-clipboard buttons (built into VitePress)
 * - Code annotations
 */

import type MarkdownIt from 'markdown-it'

export function codeEnhancerPlugin(md: MarkdownIt) {
  // VitePress already handles most code enhancements via Shiki
  // This plugin can be extended for custom code block features
  
  // Store the original fence renderer
  const defaultRender = md.renderer.rules.fence!
  
  // Override fence renderer for custom enhancements
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const token = tokens[idx]
    const info = token.info ? md.utils.unescapeAll(token.info).trim() : ''
    
    // Extract language and metadata
    const [lang, ...meta] = info.split(/\s+/)
    
    // Add custom classes or attributes based on metadata
    // For now, use default VitePress rendering
    return defaultRender(tokens, idx, options, env, self)
  }
}

/**
 * Configuration for code enhancement options
 */
export interface CodeEnhancementOptions {
  lineNumbers: boolean
  highlightLines: boolean
  copyButton: boolean
  annotations: boolean
  tabs: boolean
}

export const defaultCodeEnhancementOptions: CodeEnhancementOptions = {
  lineNumbers: true,
  highlightLines: true,
  copyButton: true,
  annotations: true,
  tabs: true
}

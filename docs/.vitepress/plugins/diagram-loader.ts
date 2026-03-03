/**
 * Diagram Loader Plugin for VitePress
 * 
 * Provides enhanced SVG diagram integration:
 * - Inline embedding
 * - Captions and descriptions
 * - Dark mode variants
 * - Zoom/fullscreen support
 */

import type MarkdownIt from 'markdown-it'

export interface DiagramConfig {
  src: string
  alt: string
  caption?: string
  darkSrc?: string
  zoomable?: boolean
}

/**
 * Embed a diagram with enhanced features
 */
export function embedDiagram(config: DiagramConfig): string {
  const { src, alt, caption, darkSrc, zoomable } = config
  
  let html = '<figure class="diagram-container">'
  
  // Add the image
  if (darkSrc) {
    // Light mode image
    html += `<img src="${src}" alt="${alt}" class="diagram light-only" />`
    // Dark mode image
    html += `<img src="${darkSrc}" alt="${alt}" class="diagram dark-only" />`
  } else {
    html += `<img src="${src}" alt="${alt}" class="diagram" />`
  }
  
  // Add caption if provided
  if (caption) {
    html += `<figcaption>${caption}</figcaption>`
  }
  
  // Add zoom indicator if zoomable
  if (zoomable) {
    html += '<span class="zoom-hint">Click to zoom</span>'
  }
  
  html += '</figure>'
  
  return html
}

/**
 * Markdown-it plugin for custom diagram syntax
 * 
 * Supports syntax like:
 * ::: diagram
 * src: /diagrams/system-architecture.svg
 * alt: System Architecture
 * caption: Complete system architecture diagram
 * zoomable: true
 * :::
 */
export function diagramLoaderPlugin(md: MarkdownIt) {
  // Custom container for diagrams
  const container = require('markdown-it-container')
  
  md.use(container, 'diagram', {
    validate: (params: string) => {
      return params.trim() === 'diagram'
    },
    
    render: (tokens: any[], idx: number) => {
      if (tokens[idx].nesting === 1) {
        // Opening tag - parse diagram config from content
        const content = tokens[idx + 1]?.content || ''
        const config = parseDiagramConfig(content)
        
        return embedDiagram(config)
      } else {
        // Closing tag
        return ''
      }
    }
  })
}

/**
 * Parse diagram configuration from markdown content
 */
function parseDiagramConfig(content: string): DiagramConfig {
  const lines = content.split('\n')
  const config: Partial<DiagramConfig> = {}
  
  for (const line of lines) {
    const [key, ...valueParts] = line.split(':')
    const value = valueParts.join(':').trim()
    
    if (key && value) {
      const trimmedKey = key.trim()
      
      if (trimmedKey === 'src') {
        config.src = value
      } else if (trimmedKey === 'alt') {
        config.alt = value
      } else if (trimmedKey === 'caption') {
        config.caption = value
      } else if (trimmedKey === 'darkSrc') {
        config.darkSrc = value
      } else if (trimmedKey === 'zoomable') {
        config.zoomable = value.toLowerCase() === 'true'
      }
    }
  }
  
  // Ensure required fields
  if (!config.src) {
    throw new Error('Diagram config missing required "src" field')
  }
  if (!config.alt) {
    config.alt = 'Diagram'
  }
  
  return config as DiagramConfig
}

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
import container from 'markdown-it-container'

export interface DiagramConfig {
  src: string
  alt: string
  caption?: string
  darkSrc?: string
  zoomable?: boolean
  description?: string  // Extended description for complex diagrams
  ariaLabel?: string    // Custom ARIA label (defaults to alt)
}

/**
 * Embed a diagram with enhanced features
 */
export function embedDiagram(config: DiagramConfig): string {
  const { src, alt, caption, darkSrc, zoomable, description, ariaLabel } = config
  
  const parts: string[] = []
  
  // Use aria-label if provided, otherwise use alt text
  const accessibleLabel = ariaLabel || alt
  
  // Add figure with proper ARIA attributes
  parts.push(`<figure class="diagram-container" role="figure" aria-label="${accessibleLabel}">`)
  
  // Add the image(s) with proper accessibility attributes
  if (darkSrc) {
    // Light mode image
    parts.push(`<img src="${src}" alt="${alt}" class="diagram light-only" role="img" aria-describedby="${description ? 'diagram-desc-' + generateId(src) : ''}">`)
    // Dark mode image
    parts.push(`<img src="${darkSrc}" alt="${alt}" class="diagram dark-only" role="img" aria-describedby="${description ? 'diagram-desc-' + generateId(src) : ''}">`)
  } else {
    parts.push(`<img src="${src}" alt="${alt}" class="diagram" role="img" aria-describedby="${description ? 'diagram-desc-' + generateId(src) : ''}">`)
  }
  
  // Add extended description for screen readers if provided
  if (description) {
    parts.push(`<div id="diagram-desc-${generateId(src)}" class="sr-only">${description}</div>`)
  }
  
  // Add caption if provided (visible to all users)
  if (caption) {
    parts.push(`<figcaption>${caption}</figcaption>`)
  }
  
  // Add zoom indicator if zoomable
  if (zoomable) {
    parts.push('<span class="zoom-hint" aria-hidden="true">Click to zoom</span>')
  }
  
  parts.push('</figure>')
  
  return parts.join('')
}

/**
 * Generate a stable ID from a source path
 */
function generateId(src: string): string {
  return src.replace(/[^a-zA-Z0-9]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '')
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
  md.use(container, 'diagram', {
    validate: (params: string) => {
      return params.trim() === 'diagram'
    },
    
    render: (tokens: any[], idx: number) => {
      const token = tokens[idx]
      
      if (token.nesting === 1) {
        // Opening tag - collect content from subsequent tokens until closing tag
        let content = ''
        let i = idx + 1
        
        // Find all content tokens until the closing tag and mark them as hidden
        while (i < tokens.length && tokens[i].nesting !== -1) {
          if (tokens[i].type === 'inline' && tokens[i].content) {
            content += tokens[i].content + '\n'
            // Mark the token as hidden so it won't be rendered
            tokens[i].hidden = true
          } else if (tokens[i].type === 'paragraph_open' || tokens[i].type === 'paragraph_close') {
            // Hide paragraph tokens too
            tokens[i].hidden = true
          }
          i++
        }
        
        // Parse and render the diagram
        try {
          const config = parseDiagramConfig(content)
          return embedDiagram(config) + '\n'
        } catch (error) {
          console.error('Diagram loader error:', error)
          return `<div class="error">Error loading diagram: ${error instanceof Error ? error.message : 'Unknown error'}</div>\n`
        }
      } else {
        // Closing tag - return empty string since we handled everything in opening tag
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
      } else if (trimmedKey === 'description') {
        config.description = value
      } else if (trimmedKey === 'ariaLabel') {
        config.ariaLabel = value
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

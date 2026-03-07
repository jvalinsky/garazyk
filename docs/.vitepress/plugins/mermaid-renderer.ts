import type MarkdownIt from 'markdown-it'

export function mermaidRendererPlugin(md: MarkdownIt) {
  const defaultRender = md.renderer.rules.fence!

  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const token = tokens[idx]
    const info = token.info ? md.utils.unescapeAll(token.info).trim() : ''
    const lang = info.split(/\s+/)[0]

    if (lang !== 'mermaid' && lang !== 'mmd') {
      return defaultRender(tokens, idx, options, env, self)
    }

    const encodedGraph = md.utils.escapeHtml(encodeURIComponent(token.content))
    return `<MermaidDiagram graph="${encodedGraph}" />`
  }
}

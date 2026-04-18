import { defineConfig } from 'vitepress'
import { sidebarConfig } from './sidebar'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: 'Garazyk Documentation',
  description: 'Contributor documentation for the Garazyk AT Protocol implementation in Objective-C',
  base: '/docs/',
  lang: 'en-US',
  
  // Appearance configuration (dark/light mode)
  appearance: 'dark', // Default to dark mode, but allow user toggle
  
  // Theme configuration
  themeConfig: {
    logo: '/logo.svg',
    siteTitle: 'Garazyk',
    
    // Navigation
    nav: [
      { text: 'Guide', link: '/01-getting-started/overview' },
      { text: 'Tutorials', link: '/10-tutorials/tutorial-1-hello-pds' },
      { text: 'Reference', link: '/11-reference/api-reference' },
      { text: 'Glossary', link: '/GLOSSARY' },
      { text: 'GitHub', link: 'https://github.com/jvalinsky/garazyk' }
    ],
    
    // Sidebar navigation
    sidebar: sidebarConfig,
    
    // Social links
    socialLinks: [
      { icon: 'github', link: 'https://github.com/jvalinsky/garazyk' }
    ],
    
    // Search configuration with MiniSearch
    search: {
      provider: 'local',
      options: {
        locales: {
          root: {
            translations: {
              button: {
                buttonText: 'Search',
                buttonAriaLabel: 'Search documentation'
              },
              modal: {
                noResultsText: 'No results for',
                resetButtonTitle: 'Clear search',
                footer: {
                  selectText: 'to select',
                  navigateText: 'to navigate',
                  closeText: 'to close'
                }
              }
            }
          }
        },
        miniSearch: {
          options: {
            fields: ['title', 'text', 'headings', 'code'],
            storeFields: ['title', 'titles', 'text'],
            searchOptions: {
              boost: { title: 4, headings: 3, text: 2, code: 1 },
              fuzzy: 0.2,
              prefix: true
            }
          },
          searchOptions: {
            fuzzy: 0.2,
            prefix: true,
            boost: {
              title: 4,
              headings: 3,
              text: 2,
              code: 1
            }
          }
        }
      }
    },
    
    // Edit link
    editLink: {
      pattern: 'https://github.com/jvalinsky/garazyk/edit/main/docs/:path',
      text: 'Edit this page on GitHub'
    },
    
    // Footer
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2024-present Garazyk Team'
    },
    
    // Last updated
    lastUpdated: {
      text: 'Last updated',
      formatOptions: {
        dateStyle: 'medium',
        timeStyle: 'short'
      }
    },
    
    // Outline configuration (table of contents)
    outline: {
      level: 'deep', // Show all heading levels (h2-h6)
      label: 'On this page'
    },
    
    // Document footer with prev/next navigation (enabled by default)
    docFooter: {
      prev: 'Previous',
      next: 'Next'
    }
  },
  
  // Markdown configuration with line numbers and syntax highlighting
  markdown: {
    lineNumbers: true,
    theme: {
      light: 'github-light',
      dark: 'github-dark'
    },
    // Language aliases for Objective-C and other languages
    languageAlias: {
      'objectivec': 'objective-c',
      'objc': 'objective-c'
    },
    // Support for code block features and diagram integration
    config: (md) => {
      // Import and use the code enhancer plugin
      const { codeEnhancerPlugin } = require('./plugins/code-enhancer')
      md.use(codeEnhancerPlugin)

      // Render Mermaid fences as interactive diagrams instead of code blocks
      const { mermaidRendererPlugin } = require('./plugins/mermaid-renderer')
      md.use(mermaidRendererPlugin)
      
      // Import and use the diagram loader plugin
      const { diagramLoaderPlugin } = require('./plugins/diagram-loader')
      md.use(diagramLoaderPlugin)
    }
  },
  
  // Head tags for SEO and meta information
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/docs/logo.svg' }],
    ['meta', { name: 'theme-color', content: '#5f67ee' }],
    ['meta', { name: 'viewport', content: 'width=device-width, initial-scale=1.0' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:locale', content: 'en' }],
    ['meta', { property: 'og:title', content: 'Garazyk Documentation' }],
    ['meta', { property: 'og:description', content: 'Contributor documentation for the Garazyk AT Protocol implementation in Objective-C' }],
    ['meta', { property: 'og:site_name', content: 'Garazyk' }],
    ['meta', { property: 'og:url', content: 'https://pds.garazyk.xyz/docs/' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:title', content: 'Garazyk Documentation' }],
    ['meta', { name: 'twitter:description', content: 'Contributor documentation for the Garazyk AT Protocol implementation in Objective-C' }]
  ],
  
  // Build configuration
  srcDir: '.',
  outDir: '.vitepress/dist',
  cacheDir: '.vitepress/cache',
  
  // Exclude directories from build
  srcExclude: ['plans/**', 'node_modules/**'],
  
  // Clean URLs (remove .html extension)
  cleanUrls: true,
  
  // Ignore dead links during build (we'll validate separately in Phase 7)
  ignoreDeadLinks: true
})

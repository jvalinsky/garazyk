import { defineConfig } from 'vitepress'
import { sidebarConfig } from './sidebar'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: 'September PDS Documentation',
  description: 'Comprehensive guide for implementing an ATProto Personal Data Server in Objective-C',
  base: '/docs/',
  lang: 'en-US',
  
  // Appearance configuration (dark/light mode)
  appearance: 'dark', // Default to dark mode, but allow user toggle
  
  // Theme configuration
  themeConfig: {
    logo: '/logo.svg',
    siteTitle: 'September PDS',
    
    // Navigation
    nav: [
      { text: 'Guide', link: '/01-getting-started/overview' },
      { text: 'Tutorials', link: '/10-tutorials/tutorial-1-hello-pds' },
      { text: 'Reference', link: '/11-reference/api-reference' },
      { text: 'Glossary', link: '/glossary' },
      { text: 'GitHub', link: 'https://github.com/user/september-pds' }
    ],
    
    // Sidebar navigation
    sidebar: sidebarConfig,
    
    // Social links
    socialLinks: [
      { icon: 'github', link: 'https://github.com/user/september-pds' }
    ],
    
    // Search configuration
    search: {
      provider: 'local',
      options: {
        miniSearch: {
          searchOptions: {
            fuzzy: 0.2,
            prefix: true,
            boost: {
              title: 4,
              heading: 3,
              text: 2
            }
          }
        }
      }
    },
    
    // Edit link
    editLink: {
      pattern: 'https://github.com/user/september-pds/edit/main/docs/:path',
      text: 'Edit this page on GitHub'
    },
    
    // Footer
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2024-present September PDS Team'
    },
    
    // Last updated
    lastUpdated: {
      text: 'Last updated',
      formatOptions: {
        dateStyle: 'medium',
        timeStyle: 'short'
      }
    },
    
    // Outline configuration
    outline: {
      level: [2, 3],
      label: 'On this page'
    }
  },
  
  // Markdown configuration with line numbers and syntax highlighting
  markdown: {
    lineNumbers: true,
    theme: {
      light: 'github-light',
      dark: 'github-dark'
    },
    // Language aliases for Objective-C
    languageAlias: {
      'objectivec': 'objective-c',
      'objc': 'objective-c',
      'dot': 'plaintext',  // Graphviz DOT not supported by Shiki, fallback to plaintext
      // PromQL is natively supported by Shiki - no alias needed
    },
    // Support for code block features
    config: (md) => {
      // Additional markdown-it plugins can be added here
      // This will be extended in Phase 4 for code enhancements
    }
  },
  
  // Head tags for SEO and meta information
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/docs/logo.svg' }],
    ['meta', { name: 'theme-color', content: '#5f67ee' }],
    ['meta', { name: 'viewport', content: 'width=device-width, initial-scale=1.0' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:locale', content: 'en' }],
    ['meta', { property: 'og:title', content: 'September PDS Documentation' }],
    ['meta', { property: 'og:description', content: 'Comprehensive guide for implementing an ATProto Personal Data Server in Objective-C' }],
    ['meta', { property: 'og:site_name', content: 'September PDS' }],
    ['meta', { property: 'og:url', content: 'https://pds.garazyk.xyz/docs/' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:title', content: 'September PDS Documentation' }],
    ['meta', { name: 'twitter:description', content: 'Comprehensive guide for implementing an ATProto Personal Data Server in Objective-C' }]
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

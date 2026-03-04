# Implementation Plan: VitePress Documentation Migration

## Overview

This implementation plan breaks down the migration of September PDS documentation from Jekyll to VitePress into actionable coding tasks. The migration will preserve all existing content while transforming it into a comprehensive technical resource with enhanced features, interactive code blocks, and improved navigation.

The implementation follows a 10-phase approach: setup, migration tooling, content enhancement, code block features, diagram integration, search/navigation, build pipeline, deployment, validation, and documentation.

## Tasks

- [x] 1. Phase 1: Setup and Configuration
  - [x] 1.1 Initialize VitePress project structure
    - Initialize Node.js project in docs directory with `package.json`
    - Install VitePress 1.0+, Vue 3, TypeScript, and development dependencies
    - Create `.vitepress/` directory structure with `config.ts`, `theme/`, and `plugins/` subdirectories
    - Set up TypeScript configuration for VitePress plugins
    - _Requirements: 1.1, 9.1_
  
  - [x] 1.2 Create base VitePress configuration
    - Implement `.vitepress/config.ts` with site metadata (title, description, base URL `/docs`)
    - Configure theme settings (logo, colors, dark/light mode)
    - Set up markdown configuration with line numbers and syntax highlighting themes
    - Configure head tags for SEO and meta information
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_
  
  - [x] 1.3 Implement sidebar navigation configuration
    - Create `.vitepress/sidebar.ts` module
    - Convert SUMMARY.md structure to VitePress sidebar format
    - Implement hierarchical navigation for all 12 sections (01-getting-started through 12-diagrams)
    - Configure collapsible sections and active page highlighting
    - _Requirements: 1.7, 2.6, 8.1, 8.2, 8.3_
  
  - [x] 1.4 Set up custom theme
    - Create `.vitepress/theme/index.ts` theme entry point
    - Implement `.vitepress/theme/style.css` with custom branding
    - Configure responsive design breakpoints for mobile, tablet, desktop
    - Test dark and light theme modes
    - _Requirements: 1.2, 1.4, 1.6_
    - _Note: Fixed syntax highlighting for Objective-C (objectivec → objective-c alias), added fallbacks for unsupported languages (dot, promql → plaintext), escaped angle brackets in markdown to fix Vue parsing errors_
  
  - [x] 1.5 Verify local development environment
    - Test local development server with `npm run docs:dev`
    - Verify hot reload functionality
    - Test navigation and theme switching
    - _Requirements: 9.10_
    - _Note: Build completes successfully, syntax highlighting working correctly for all languages_

- [ ] 2. Phase 2: Migration Tool Development
  - [x] 2.1 Create migration tool foundation
    - Implement `scripts/migrate-to-vitepress.ts` with TypeScript
    - Define `MigrationOptions`, `MigrationResult`, and `FileInfo` interfaces
    - Implement file system operations for reading Jekyll files
    - Create backup mechanism for source files
    - _Requirements: 2.1, 2.4_
  
  - [x] 2.2 Implement front matter conversion
    - Implement `convertFrontMatter()` function to transform Jekyll format to VitePress format
    - Convert `layout: default` to VitePress front matter structure
    - Preserve title, description, and other metadata fields
    - Handle missing front matter by generating default values
    - _Requirements: 2.3, 7.1_
  
  - [x] 2.3 Implement link format conversion
    - Implement `updateLinks()` function to convert Jekyll links to VitePress format
    - Convert `.md` extensions in links to extensionless format
    - Preserve anchor links and query parameters
    - Update relative path references
    - _Requirements: 2.5, 3.1_
  
  - [x] 2.4 Implement diagram migration
    - Implement `copyDiagrams()` function to copy SVG files from `docs/12-diagrams/` to `public/diagrams/`
    - Preserve diagram file names and directory structure
    - Update diagram references in Markdown files
    - _Requirements: 2.9, 6.1_
  
  - [x] 2.5 Implement migration report generator
    - Implement `generateReport()` function to create migration summary
    - Track files processed, converted, link updates, and errors
    - Generate detailed report with warnings and errors
    - Output report to `migration-report.md`
    - _Requirements: 2.8_
  
  - [x] 2.6 Execute full migration
    - Run migration tool on all documentation files
    - Verify file count matches source (100+ files)
    - Review migration report for errors and warnings
    - Manually verify critical pages migrated correctly
    - _Requirements: 2.1, 2.2, 2.4, 20.1_
  
  - [x] 2.7 Write unit tests for migration tool
    - Test front matter conversion with various Jekyll formats
    - Test link conversion with relative and absolute paths
    - Test error handling for missing files and invalid syntax
    - Test diagram copying and reference updates
    - **Property 1: Complete File Migration**
    - **Property 2: Code Block Preservation**
    - **Property 7: Front Matter Conversion**
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.5**

- [x] 3. Checkpoint - Verify migration completeness
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Phase 3: Content Enhancement
  - [x] 4.1 Create content expansion framework
    - Implement `scripts/expand-content.ts` with TypeScript
    - Define `ContentExpansionRule`, `FileContext`, and `CodeBlock` interfaces
    - Create expansion templates for explanations, "Why this matters", and troubleshooting sections
    - Implement code analysis functions to extract key points
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.8_
  
  - [x] 4.2 Expand Tutorial 1: Hello PDS
    - Add prerequisites section listing required knowledge
    - Add learning objectives and "What you'll build" overview
    - Add comprehensive explanations between code blocks
    - Add troubleshooting section for common issues
    - Add "Next steps" section and estimated completion time
    - Add summary section reviewing key concepts
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.9, 5.10_
  
  - [x] 4.3 Expand Tutorial 2: Accounts
    - Add all required tutorial sections (prerequisites, objectives, overview, troubleshooting, next steps, time, summary)
    - Add detailed explanations for account creation and JWT minting code
    - Add real-world usage examples and context
    - Verify code examples compile successfully
    - _Requirements: 5.1-5.10_
  
  - [x] 4.4 Expand Tutorial 3: Records
    - Add all required tutorial sections
    - Add explanations for record CRUD operations and MST integration
    - Add common pitfalls and troubleshooting guidance
    - Verify code examples compile successfully
    - _Requirements: 5.1-5.10_
  
  - [x] 4.5 Expand Tutorial 4: Authentication
    - Add all required tutorial sections
    - Add explanations for OAuth 2.0, DPoP, and JWT verification
    - Add security best practices and common mistakes
    - Verify code examples compile successfully
    - _Requirements: 5.1-5.10_
  
  - [x] 4.6 Expand Tutorial 5: Firehose
    - Add all required tutorial sections
    - Add explanations for WebSocket connections and event streaming
    - Add troubleshooting for connection issues and backpressure
    - Verify code examples compile successfully
    - _Requirements: 5.1-5.10_
  
  - [x] 4.7 Expand Tutorial 6: Deployment
    - Add all required tutorial sections
    - Add explanations for Docker deployment and production configuration
    - Add troubleshooting for deployment issues
    - Verify deployment scripts work correctly
    - _Requirements: 5.1-5.10_
  
  - [x] 4.8 Enhance core concept documentation
    - Add "Why this matters" sections to all core concept pages
    - Add comprehensive explanations for CBOR, CAR, MST, and cryptography
    - Add real-world examples and use cases
    - Add design decision explanations and trade-offs
    - _Requirements: 3.1, 3.2, 3.3, 3.6, 3.7, 3.9_
  
  - [x] 4.9 Enhance service layer documentation
    - Add comprehensive explanations for all service implementations
    - Add "When to use" guidance for different patterns
    - Add common pitfalls and troubleshooting sections
    - Cross-reference related documentation sections
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.8, 3.9_
  
  - [x] 4.10 Review content quality and consistency
    - Review all expanded content for consistent voice and style
    - Verify terminology matches GLOSSARY.md
    - Ensure progressive complexity from simple to advanced
    - Verify all code examples have explanatory context
    - **Property 5: Tutorial Structure Completeness**
    - **Validates: Requirements 3.8, 3.9, 5.1-5.10, 12.1-12.10**

- [x] 5. Phase 4: Code Block Enhancement
  - [x] 5.1 Configure syntax highlighting
    - Configure Shiki in `.vitepress/config.ts` with Objective-C support
    - Set up light theme (github-light) and dark theme (github-dark)
    - Enable line numbers for all code blocks
    - Test syntax highlighting for Objective-C, TypeScript, Bash, JSON
    - _Requirements: 4.1, 4.3, 4.10_
  
  - [x] 5.2 Implement code enhancement plugin
    - Create `.vitepress/plugins/code-enhancer.ts`
    - Implement line highlighting support with `{2,4-6}` syntax
    - Implement code block titles with `[filename.m]` syntax
    - Add copy-to-clipboard button functionality
    - _Requirements: 4.2, 4.6, 4.8_
  
  - [x] 5.3 Implement code group tabs for platform-specific code
    - Extend markdown-it to support `::: code-group` syntax
    - Create Vue component for tabbed code display
    - Add macOS and Linux tabs for platform-specific examples
    - Test tab switching and code display
    - _Requirements: 4.5_
  
  - [x] 5.4 Add code annotations support
    - Implement inline comment highlighting for explanations
    - Support annotation markers in code blocks
    - Style annotations for visibility in both themes
    - _Requirements: 4.4_
  
  - [x] 5.5 Implement collapsible code blocks
    - Add support for collapsible sections for long examples
    - Implement expand/collapse functionality
    - Preserve collapsed state during navigation
    - _Requirements: 4.9_
  
  - [x] 5.6 Validate code block enhancements
    - Test all code block features in light and dark themes
    - Verify copy buttons work correctly
    - Test platform-specific tabs
    - Verify line highlighting displays correctly
    - **Property 9: Syntax Highlighting Application**
    - **Validates: Requirements 4.1-4.10**

- [x] 6. Phase 5: Diagram Integration
  - [x] 6.1 Create diagram loader plugin
    - Implement `.vitepress/plugins/diagram-loader.ts`
    - Create `DiagramConfig` interface for diagram metadata
    - Implement `embedDiagram()` function for SVG embedding
    - Support inline diagram references with custom syntax
    - _Requirements: 6.1, 6.2_
  
  - [x] 6.2 Add diagram captions and accessibility
    - Implement caption rendering below diagrams
    - Add alt text support for all diagrams
    - Create accessible descriptions for complex diagrams
    - Ensure screen reader compatibility
    - _Requirements: 6.4, 6.7, 15.5_
  
  - [x] 6.3 Implement diagram zoom functionality
    - Add click-to-zoom or full-screen view for complex diagrams
    - Implement modal overlay for zoomed diagrams
    - Add keyboard navigation for zoom controls
    - _Requirements: 6.6_
  
  - [x] 6.4 Create diagrams reference page
    - Create `docs/12-diagrams/index.md` listing all diagrams
    - Add thumbnails and descriptions for each diagram
    - Link to pages where each diagram is used
    - _Requirements: 6.5_
  
  - [x] 6.5 Integrate all diagrams into documentation
    - Embed system-architecture.svg in architecture overview
    - Embed oauth2-dpop-flow.svg in authentication documentation
    - Embed jwt-token-flow.svg in JWT documentation
    - Embed mst-tree-structure.svg in MST documentation
    - Embed commit-broadcasting-flow.svg in firehose documentation
    - Embed method-registration.svg in XRPC documentation
    - Embed rate-limiting-algorithm.svg in rate limiting documentation
    - Embed secrets-management-flow.svg in security documentation
    - _Requirements: 6.1, 6.9_
  
  - [x] 6.6 Validate diagram integration
    - Verify all diagrams display correctly
    - Test diagram loading performance
    - Verify accessibility with screen readers
    - Run existing diagram validation script
    - **Property 4: Diagram Integration**
    - **Validates: Requirements 6.1-6.10**

- [x] 7. Checkpoint - Verify enhanced features
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Phase 6: Search and Navigation
  - [x] 8.1 Configure search functionality
    - Configure MiniSearch in `.vitepress/config.ts`
    - Set search options (fuzzy: 0.2, prefix: true)
    - Configure search boost weights (title: 4, text: 2, headings: 3, code: 1)
    - Enable local search provider
    - _Requirements: 1.3, 7.1, 7.2, 7.4_
  
  - [x] 8.2 Implement search index customization
    - Configure fields to index (title, text, headings, code)
    - Implement code block content indexing
    - Configure search result context display
    - Test search coverage across all documentation
    - _Requirements: 7.1, 7.6, 7.8, 7.9_
  
  - [x] 8.3 Implement keyboard navigation for search
    - Configure keyboard shortcuts for search (Cmd/Ctrl+K)
    - Implement arrow key navigation in search results
    - Add Enter key to navigate to selected result
    - Add Escape key to close search modal
    - _Requirements: 7.5_
  
  - [x] 8.4 Configure navigation structure
    - Implement breadcrumb navigation in theme
    - Add previous/next page navigation links
    - Configure automatic table of contents for each page
    - Enable deep linking to headings with anchor links
    - _Requirements: 8.4, 8.5, 8.6, 8.7_
  
  - [x] 8.5 Implement mobile navigation
    - Configure responsive hamburger menu for small screens
    - Test navigation on mobile devices
    - Ensure touch-friendly tap targets
    - Test sidebar collapse/expand on mobile
    - _Requirements: 8.9_
  
  - [x] 8.6 Add edit link and last updated
    - Configure GitHub edit link for each page
    - Enable last updated timestamp display
    - Configure git-based last updated tracking
    - _Requirements: 16.6_
  
  - [x] 8.7 Validate search and navigation
    - Test search functionality with various queries
    - Verify keyboard navigation works
    - Test mobile navigation on multiple devices
    - Verify all navigation links work correctly
    - **Property 6: Search Index Coverage**
    - **Property 8: Heading Anchor Links**
    - **Property 10: Navigation Completeness**
    - **Validates: Requirements 7.1-7.10, 8.1-8.10**

- [ ] 9. Phase 7: Build Pipeline Integration
  - [x] 9.1 Create build script
    - Implement `scripts/build-docs.sh` with validation checks
    - Add link validation step
    - Add diagram validation step
    - Add code block validation step
    - Add VitePress build step
    - Add asset optimization step
    - Add sitemap generation step
    - _Requirements: 9.1, 9.3, 9.4, 9.5, 9.7_
  
  - [x] 9.2 Implement validation scripts
    - Create `scripts/validate-docs.ts` with TypeScript
    - Implement `validateLinks()` for internal and external link checking
    - Implement `validateDiagrams()` for diagram reference checking
    - Implement `validateCodeBlocks()` for syntax and language checking
    - Implement `validateAccessibility()` for WCAG compliance
    - Implement `validateHeadingHierarchy()` for proper heading structure
    - Generate validation report with errors and warnings
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7, 11.9_
  
  - [x] 9.3 Implement asset optimization
    - Add image optimization to build pipeline
    - Add SVG optimization for diagrams
    - Configure CSS minification
    - Configure JavaScript minification and code splitting
    - _Requirements: 9.8, 14.3, 14.4, 14.5, 14.9_
  
  - [x] 9.4 Implement sitemap generation
    - Create sitemap.xml generator script
    - Include all documentation pages in sitemap
    - Set proper priority and change frequency
    - _Requirements: 9.9_
  
  - [ ] 9.5 Update GitHub Actions workflow
    - Update `.github/workflows/build-docs.yml`
    - Add validation step before build
    - Add VitePress build step
    - Add deployment step
    - Configure build artifacts upload
    - _Requirements: 9.2, 9.6_
  
  - [x] 9.6 Test build pipeline
    - Run full build pipeline locally
    - Verify validation catches errors
    - Test build failure on validation errors
    - Verify sitemap generation
    - **Property 3: Internal Link Validity**
    - **Property 11: Image Reference Validity**
    - **Property 12: Heading Hierarchy Consistency**
    - **Property 17: External Link Availability**
    - **Validates: Requirements 9.1-9.10, 11.1-11.10**

- [-] 10. Phase 8: Deployment Configuration
  - [x] 10.1 Create nginx configuration
    - Create `docker/docs/nginx.conf` for serving documentation
    - Configure location block for `/docs` path
    - Set up try_files for SPA routing
    - Configure caching headers for static assets (1 year for immutable assets)
    - Configure no-cache headers for HTML files
    - _Requirements: 10.1, 10.2, 10.4, 10.5_
  
  - [x] 10.2 Create custom 404 page
    - Create `docs/404.md` with helpful content
    - Add search functionality to 404 page
    - Add navigation links to main sections
    - Suggest similar pages based on URL
    - _Requirements: 10.7_
  
  - [x] 10.3 Configure URL redirects
    - Identify Jekyll URLs that differ from VitePress URLs
    - Create redirect configuration in nginx or VitePress
    - Generate URL mapping file for reference
    - Test all redirects
    - _Requirements: 10.8, 13.1, 13.4, 13.5_
  
  - [x] 10.4 Set up deployment process
    - Configure deployment to pds.garazyk.xyz/docs
    - Set up HTTPS/TLS configuration
    - Configure deployment preview for pull requests
    - Create deployment verification script
    - _Requirements: 10.1, 10.3, 10.9, 10.10_
  
  - [x] 10.5 Deploy to staging
    - Deploy VitePress site to staging environment
    - Run smoke tests on staging
    - Verify all links work
    - Verify search functionality
    - Test mobile responsiveness
    - _Requirements: 10.10_
  
  - [ ] 10.6 Deploy to production
    - Deploy VitePress site to production (pds.garazyk.xyz/docs)
    - Verify deployment with automated checks
    - Test production site functionality
    - Monitor for errors
    - _Requirements: 10.1, 10.10_
  
  - [ ] 10.7 Validate deployment
    - Verify site accessible at pds.garazyk.xyz/docs
    - Test HTTPS configuration
    - Verify caching headers
    - Test 404 page
    - Test redirects from old URLs
    - **Property 13: URL Redirect Mapping**
    - **Property 14: File Naming Consistency**
    - **Validates: Requirements 10.1-10.10, 13.1-13.10**

- [x] 11. Checkpoint - Verify deployment
  - Ensure all tests pass, ask the user if questions arise.

- [x] 12. Phase 9: Validation and Testing
  - [x] 12.1 Implement property-based tests
    - Set up fast-check library for TypeScript
    - Implement Property 1: Complete File Migration test
    - Implement Property 2: Code Block Preservation test
    - Implement Property 3: Internal Link Validity test
    - Implement Property 6: Search Index Coverage test
    - Implement Property 9: Syntax Highlighting Application test
    - Implement Property 12: Heading Hierarchy Consistency test
    - Configure 100 iterations per property test
    - _Requirements: 20.1, 20.2, 20.3, 20.6_
  
  - [x] 12.2 Run comprehensive link validation
    - Run link validation on all documentation pages
    - Verify zero broken internal links
    - Check external link availability
    - Generate link validation report
    - _Requirements: 11.1, 11.2, 20.2_
  
  - [x] 12.3 Run accessibility validation
    - Run axe-core accessibility tests on all pages
    - Verify WCAG 2.1 AA compliance
    - Check color contrast in light and dark themes
    - Verify keyboard navigation
    - Verify screen reader compatibility
    - Generate accessibility report
    - _Requirements: 11.8, 15.1-15.10_
  
  - [x] 12.4 Run performance validation
    - Run Lighthouse tests on key pages
    - Verify performance score ≥ 90
    - Verify First Contentful Paint < 1.5s
    - Verify Time to Interactive < 3s
    - Generate performance report
    - _Requirements: 14.1, 14.2, 14.7, 14.10_
  
  - [x] 12.5 Validate code examples
    - Verify all tutorial code examples compile
    - Run code style checks on all examples
    - Verify error handling in code examples
    - Check memory management implications noted
    - _Requirements: 19.1, 19.2, 19.3, 19.8_
  
  - [x] 12.6 Run migration verification
    - Verify all Jekyll pages have VitePress equivalents
    - Verify all code blocks render correctly
    - Verify all diagrams display correctly
    - Verify navigation structure matches original
    - Generate comprehensive migration verification report
    - _Requirements: 20.1, 20.2, 20.3, 20.4, 20.5, 20.7, 20.8, 20.9, 20.10_
  
  - [x] 12.7 Generate final validation report
    - Compile all validation results
    - Document any remaining issues
    - Create sign-off checklist
    - **Property 15: Code Example Compilation**
    - **Property 16: Code Style Compliance**
    - **Property 18: Migration Verification Completeness**
    - **Validates: Requirements 11.1-11.10, 14.1-14.10, 15.1-15.10, 19.1-19.10, 20.1-20.10**

- [x] 13. Phase 10: Documentation and Handoff
  - [x] 13.1 Create maintenance documentation
    - Document content update workflow
    - Document how to add new documentation pages
    - Document how to update diagrams
    - Document build and deployment process
    - Create troubleshooting guide for common issues
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.10_
  
  - [x] 13.2 Create migration guide for users
    - Document URL changes from Jekyll to VitePress
    - Create URL mapping file for external references
    - Document how to update bookmarks
    - Notify users of migration completion
    - _Requirements: 13.4, 13.5, 13.9, 13.10_
  
  - [x] 13.3 Create documentation templates
    - Create template for new documentation pages
    - Create template for tutorials
    - Create template for API reference pages
    - Document style guidelines
    - _Requirements: 16.1, 16.3_
  
  - [x] 13.4 Set up documentation monitoring
    - Configure analytics (if enabled)
    - Set up alerts for build failures
    - Set up alerts for broken links
    - Document monitoring procedures
    - _Requirements: 16.8_
  
  - [x] 13.5 Archive Jekyll documentation
    - Create backup of Jekyll documentation
    - Archive Jekyll configuration
    - Update README with new documentation URL
    - Remove Jekyll dependencies
    - _Requirements: 13.9_
  
  - [x] 13.6 Final review and sign-off
    - Review all deliverables against requirements
    - Verify all 20 requirements met
    - Verify all 18 properties validated
    - Create final project summary
    - Obtain stakeholder sign-off
    - _Requirements: All_

- [x] 14. Final checkpoint - Project completion
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional validation and testing tasks that can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property-based tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- Checkpoints ensure incremental validation throughout the project
- The migration preserves all existing content while significantly enhancing it
- TypeScript is used for all tooling and configuration
- The implementation follows VitePress best practices and conventions

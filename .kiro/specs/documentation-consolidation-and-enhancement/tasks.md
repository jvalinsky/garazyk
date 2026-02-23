# Implementation Plan: Documentation Consolidation and Enhancement

## Overview

This plan implements a comprehensive documentation reorganization system using JavaScript/Node.js. The implementation consolidates fragmented documentation across multiple directories, fills critical gaps in deployment and troubleshooting guides, establishes quality standards, and implements an archive management strategy.

## Tasks

- [x] 1. Set up project structure and dependencies
  - Create `scripts/docs/` directory for documentation tooling
  - Initialize package.json with required dependencies (fs-extra, glob, gray-matter, marked, mermaid-cli, js-yaml)
  - Set up ESLint configuration for documentation scripts
  - _Requirements: 14.1, 14.2_

- [ ] 2. Implement core migration tool
  - [x] 2.1 Create migration configuration schema
    - Define JSON schema for migration mappings (source, destination, file patterns)
    - Implement configuration validator
    - Create example migration config for plan/ and plans/ directories
    - _Requirements: 14.1, 14.2_

  - [-] 2.2 Implement file discovery and filtering
    - Write function to recursively scan source directories
    - Implement glob pattern matching for file selection
    - Add exclusion patterns for .git, node_modules, etc.
    - _Requirements: 1.1, 14.3_

  - [ ] 2.3 Implement git mv operations
    - Write function to execute git mv commands for history preservation
    - Add batch processing for multiple files
    - Implement error handling and rollback on failure
    - _Requirements: 1.4, 14.3, 14.6_

  - [ ] 2.4 Write property test for file consolidation completeness
    - **Property 1: File Consolidation Completeness**
    - **Validates: Requirements 1.1**

  - [ ] 2.5 Write property test for git history preservation
    - **Property 2: Git History Preservation**
    - **Validates: Requirements 1.4, 14.3**

- [ ] 3. Implement link and reference updating
  - [ ] 3.1 Create Markdown link parser
    - Parse Markdown files to extract all links (relative, absolute, anchors)
    - Identify internal vs external links
    - Extract cross-references and file paths
    - _Requirements: 2.1, 2.2_

  - [ ] 3.2 Implement path resolution logic
    - Calculate new relative paths based on file moves
    - Handle different link formats ([text](path), <path>, bare URLs)
    - Update anchor links to reflect new file locations
    - _Requirements: 2.1, 2.2, 2.5_

  - [ ] 3.3 Implement file content updater
    - Read file content, update links, write back atomically
    - Preserve file permissions and timestamps
    - Handle UTF-8 encoding correctly
    - _Requirements: 2.1, 2.4, 14.4_

  - [ ] 3.4 Write property test for link resolution after migration
    - **Property 3: Link Resolution After Migration**
    - **Validates: Requirements 2.1, 2.2, 2.5**

  - [ ] 3.5 Write property test for cross-reference update correctness
    - **Property 6: Cross-Reference Update Correctness**
    - **Validates: Requirements 2.1, 14.4**

- [ ] 4. Implement migration mapping and reporting
  - [ ] 4.1 Create migration mapping generator
    - Generate JSON file mapping old paths to new paths
    - Include file metadata (size, last modified, git commit)
    - _Requirements: 1.5, 14.5_

  - [ ] 4.2 Implement migration report generator
    - Create detailed report with statistics (files moved, links updated, errors)
    - Include validation results for all moved files
    - Generate human-readable summary
    - _Requirements: 14.5_

  - [ ] 4.3 Write property test for migration mapping completeness
    - **Property 5: Migration Mapping Completeness**
    - **Validates: Requirements 1.5**

  - [ ] 4.4 Write property test for migration report generation
    - **Property 27: Migration Report Generation**
    - **Validates: Requirements 14.5**

- [ ] 5. Checkpoint - Ensure migration tool tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement directory cleanup
  - [ ] 6.1 Create empty directory detector
    - Recursively scan source directories after migration
    - Identify directories with no files (excluding .git)
    - _Requirements: 1.3_

  - [ ] 6.2 Implement safe directory removal
    - Verify directory is truly empty before removal
    - Remove directories recursively from deepest to shallowest
    - Log all removals for audit trail
    - _Requirements: 1.3_

  - [ ] 6.3 Write property test for empty directory cleanup
    - **Property 4: Empty Directory Cleanup**
    - **Validates: Requirements 1.3**

- [ ] 7. Implement documentation validator
  - [ ] 7.1 Create Markdown linter integration
    - Integrate markdownlint-cli for formatting validation
    - Configure rules for consistent style (heading levels, list formatting, line length)
    - Generate lint reports with file locations and error details
    - _Requirements: 11.1, 11.6_

  - [ ] 7.2 Implement link validator
    - Extract all internal links from Markdown files
    - Verify each link resolves to existing file or anchor
    - Report broken links with source file and line number
    - _Requirements: 11.2, 11.6_

  - [ ] 7.3 Implement code block validator
    - Parse all code blocks from Markdown files
    - Verify each code block has language identifier
    - Check for common syntax errors in code blocks
    - _Requirements: 11.3, 11.6_

  - [ ] 7.4 Write property test for markdown formatting consistency
    - **Property 17: Markdown Formatting Consistency**
    - **Validates: Requirements 11.1**

  - [ ] 7.5 Write property test for internal link validity
    - **Property 18: Internal Link Validity**
    - **Validates: Requirements 11.2**

  - [ ] 7.6 Write property test for code block language tags
    - **Property 19: Code Block Language Tags**
    - **Validates: Requirements 11.3**

- [ ] 8. Implement Mermaid diagram validator
  - [ ] 8.1 Create Mermaid syntax validator
    - Use mermaid-cli to validate diagram syntax
    - Extract all Mermaid diagrams from Markdown files
    - Report syntax errors with diagram location
    - _Requirements: 11.4, 11.6_

  - [ ] 8.2 Implement diagram rendering test
    - Attempt to render each diagram to SVG
    - Verify rendering completes without errors
    - Cache validation results for performance
    - _Requirements: 11.4, 11.6_

  - [ ] 8.3 Write property test for diagram syntax validity
    - **Property 13: Diagram Syntax Validity**
    - **Validates: Requirements 7.5, 7.6**

  - [ ] 8.4 Write property test for Mermaid diagram rendering
    - **Property 20: Mermaid Diagram Rendering**
    - **Validates: Requirements 11.4**

- [ ] 9. Implement code example validator
  - [ ] 9.1 Create code example extractor
    - Extract code blocks marked as examples from documentation
    - Identify language and create temporary files
    - Handle multi-file examples
    - _Requirements: 8.1, 8.5_

  - [ ] 9.2 Implement compilation test runner
    - Compile extracted code examples using appropriate compiler/interpreter
    - Capture compilation errors and warnings
    - Report failures with example location
    - _Requirements: 8.2, 8.5, 8.6_

  - [ ] 9.3 Implement style checker integration
    - Run project linter on extracted code examples
    - Verify examples follow coding standards
    - Report style violations
    - _Requirements: 8.4, 8.6_

  - [ ] 9.4 Write property test for code example compilation
    - **Property 8: Code Example Compilation**
    - **Validates: Requirements 8.2, 8.5**

  - [ ] 9.5 Write property test for code example style consistency
    - **Property 9: Code Example Style Consistency**
    - **Validates: Requirements 8.4, 8.6**

  - [ ] 9.6 Write property test for code example completeness
    - **Property 10: Code Example Completeness**
    - **Validates: Requirements 8.3**

- [ ] 10. Checkpoint - Ensure validation tool tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Implement API documentation validator
  - [ ] 11.1 Create API documentation structure checker
    - Define required sections for API docs (request, response, auth, errors, examples)
    - Parse API documentation files
    - Verify all required sections present
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 11.5_

  - [ ] 11.2 Implement schema validator
    - Verify request/response schemas are valid JSON Schema
    - Check for required fields documentation
    - Validate example requests/responses match schemas
    - _Requirements: 9.2, 9.3, 9.6_

  - [ ] 11.3 Write property test for endpoint documentation structure
    - **Property 11: Endpoint Documentation Structure**
    - **Validates: Requirements 9.2, 9.3, 9.4, 9.5, 9.6**

  - [ ] 11.4 Write property test for API documentation completeness
    - **Property 21: API Documentation Completeness**
    - **Validates: Requirements 11.5**

- [ ] 12. Implement archive management system
  - [ ] 12.1 Create archive manager
    - Implement function to move files to docs/archive/ with timestamp
    - Generate archive metadata (original path, timestamp, reason, author)
    - Preserve original file content byte-for-byte
    - _Requirements: 10.1, 10.3, 10.4_

  - [ ] 12.2 Implement archive index generator
    - Create/update docs/archive/INDEX.md with all archived files
    - Include metadata table (filename, date, reason, original location)
    - Sort by date descending
    - _Requirements: 10.2_

  - [ ] 12.3 Create archive review scheduler
    - Implement quarterly review reminder system
    - Generate report of documentation age
    - Identify candidates for archival
    - _Requirements: 10.5_

  - [ ] 12.4 Write property test for archive metadata completeness
    - **Property 14: Archive Metadata Completeness**
    - **Validates: Requirements 10.1, 10.3**

  - [ ] 12.5 Write property test for archive index completeness
    - **Property 15: Archive Index Completeness**
    - **Validates: Requirements 10.2**

  - [ ] 12.6 Write property test for archive file preservation
    - **Property 16: Archive File Preservation**
    - **Validates: Requirements 10.4**

- [ ] 13. Execute directory consolidation
  - [ ] 13.1 Run migration for plan/ directory
    - Execute migration tool with plan/ as source, docs/plans/ as destination
    - Verify all files moved successfully
    - Verify all links updated correctly
    - _Requirements: 1.1, 1.2, 1.4, 1.5_

  - [ ] 13.2 Run migration for plans/ directory
    - Execute migration tool with plans/ as source, docs/plans/ as destination
    - Verify all files moved successfully
    - Verify all links updated correctly
    - _Requirements: 1.1, 1.2, 1.4, 1.5_

  - [ ] 13.3 Clean up empty source directories
    - Run directory cleanup tool
    - Verify plan/ and plans/ removed if empty
    - _Requirements: 1.3_

  - [ ] 13.4 Validate consolidated structure
    - Run full validation suite on docs/ directory
    - Verify all links resolve
    - Generate validation report
    - _Requirements: 2.5_

- [ ] 14. Create developer guide
  - [ ] 14.1 Write build system documentation
    - Document XcodeGen project generation
    - Document all build targets (CLI, Tests, Fuzzers)
    - Provide example build commands for macOS and Linux
    - _Requirements: 3.1, 3.2_

  - [ ] 14.2 Write testing documentation
    - Document unit test framework and execution
    - Document property-based testing approach
    - Document integration test setup
    - _Requirements: 3.3_

  - [ ] 14.3 Write debugging guide
    - Document common debugging scenarios
    - Provide lldb/gdb command examples
    - Document logging configuration
    - _Requirements: 3.4_

  - [ ] 14.4 Write contribution guide
    - Document code review process
    - Document commit message conventions
    - Document PR workflow
    - _Requirements: 3.5_

  - [ ] 14.5 Write unit tests for developer guide examples
    - Test all code examples compile
    - Test all commands execute successfully
    - _Requirements: 8.2, 8.5_

- [ ] 15. Create deployment guides
  - [ ] 15.1 Write Docker deployment guide
    - Document Docker image build process
    - Document docker-compose configuration
    - Provide production deployment example
    - _Requirements: 4.1_

  - [ ] 15.2 Write VM deployment guide
    - Document VM setup and dependencies
    - Document nginx reverse proxy configuration
    - Provide systemd service example
    - _Requirements: 4.1_

  - [ ] 15.3 Write development environment guide
    - Document local development setup
    - Document IDE configuration (Xcode, VSCode)
    - Provide troubleshooting for common setup issues
    - _Requirements: 4.1_

  - [ ] 15.4 Document configuration options
    - Create comprehensive config reference
    - Document all options with types and defaults
    - Highlight secure defaults and production requirements
    - _Requirements: 4.2_

  - [ ] 15.5 Create security checklist
    - Document mandatory production settings
    - Provide security hardening recommendations
    - Include common security pitfalls
    - _Requirements: 4.3_

  - [ ] 15.6 Write monitoring and logging guide
    - Document log configuration and rotation
    - Provide monitoring setup examples
    - Document key metrics to track
    - _Requirements: 4.4_

  - [ ] 15.7 Write backup and recovery guide
    - Document database backup procedures
    - Document disaster recovery steps
    - Provide restore testing procedures
    - _Requirements: 4.5_

  - [ ] 15.8 Write upgrade guide
    - Document upgrade process and precautions
    - Provide rollback procedures
    - Document breaking changes by version
    - _Requirements: 4.6_

- [ ] 16. Checkpoint - Ensure deployment guides are complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 17. Create performance guide
  - [ ] 17.1 Write SQLite optimization guide
    - Document WAL mode configuration
    - Document prepared statement usage
    - Provide query optimization examples
    - _Requirements: 5.1_

  - [ ] 17.2 Write WebSocket optimization guide
    - Document connection pooling
    - Document backpressure handling
    - Provide scaling recommendations
    - _Requirements: 5.2_

  - [ ] 17.3 Write rate limiting guide
    - Document rate limit configuration
    - Provide tuning recommendations
    - Document bypass mechanisms for trusted clients
    - _Requirements: 5.3_

  - [ ] 17.4 Write benchmarking guide
    - Provide benchmark scripts
    - Document performance testing methodology
    - Include baseline performance metrics
    - _Requirements: 5.4_

  - [ ] 17.5 Write resource requirements guide
    - Document CPU/memory requirements by scale
    - Provide capacity planning guidance
    - Include scaling thresholds
    - _Requirements: 5.5_

- [ ] 18. Create troubleshooting guides
  - [ ] 18.1 Write authentication troubleshooting guide
    - Document common auth failure scenarios
    - Provide diagnostic commands
    - Include resolution steps for each scenario
    - _Requirements: 6.1, 6.5, 6.6_

  - [ ] 18.2 Write repository sync troubleshooting guide
    - Document sync failure scenarios
    - Provide MST debugging techniques
    - Include CAR file validation procedures
    - _Requirements: 6.2, 6.5, 6.6_

  - [ ] 18.3 Write WebSocket troubleshooting guide
    - Document connection failure scenarios
    - Provide WebSocket debugging tools
    - Include event broadcasting diagnostics
    - _Requirements: 6.3, 6.5, 6.6_

  - [ ] 18.4 Write PLC integration troubleshooting guide
    - Document PLC operation failure scenarios
    - Provide DID resolution debugging steps
    - Include signature verification diagnostics
    - _Requirements: 6.4, 6.5, 6.6_

- [ ] 19. Create enhanced diagrams
  - [ ] 19.1 Create OAuth2 flow diagram
    - Diagram client registration flow
    - Diagram authorization code flow
    - Diagram token refresh flow
    - Diagram DPoP proof generation
    - _Requirements: 7.1, 7.5, 7.6_

  - [ ] 19.2 Create repository commit flow diagram
    - Diagram MST update operations
    - Diagram CAR file generation
    - Diagram commit signing
    - _Requirements: 7.2, 7.5, 7.6_

  - [ ] 19.3 Create WebSocket subscription flow diagram
    - Diagram connection establishment
    - Diagram event broadcasting
    - Diagram cursor management
    - _Requirements: 7.3, 7.5, 7.6_

  - [ ] 19.4 Create PLC operation flow diagram
    - Diagram DID resolution
    - Diagram operation signing
    - Diagram operation submission
    - _Requirements: 7.4, 7.5, 7.6_

  - [ ] 19.5 Validate all diagrams render correctly
    - Run Mermaid validator on all diagrams
    - Verify rendering to SVG succeeds
    - _Requirements: 7.5, 7.6, 11.4_

- [ ] 20. Create API documentation
  - [ ] 20.1 Document authentication endpoints
    - Document com.atproto.server.createSession
    - Document com.atproto.server.refreshSession
    - Document com.atproto.server.getServiceAuth
    - Include request/response schemas, auth requirements, errors, examples
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

  - [ ] 20.2 Document repository endpoints
    - Document com.atproto.repo.createRecord
    - Document com.atproto.repo.putRecord
    - Document com.atproto.repo.deleteRecord
    - Document com.atproto.repo.getRecord
    - Include request/response schemas, auth requirements, errors, examples
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

  - [ ] 20.3 Document sync endpoints
    - Document com.atproto.sync.subscribeRepos
    - Document com.atproto.sync.getRepo
    - Include request/response schemas, auth requirements, errors, examples
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

  - [ ] 20.4 Document admin endpoints
    - Document com.atproto.admin.disableAccount
    - Document com.atproto.admin.enableAccount
    - Include request/response schemas, auth requirements, errors, examples
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

  - [ ] 20.5 Validate API documentation completeness
    - Run API documentation validator
    - Verify all required sections present
    - Verify schemas are valid
    - _Requirements: 11.5_

- [ ] 21. Checkpoint - Ensure content creation is complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 22. Create code examples for public APIs
  - [ ] 22.1 Create repository API examples
    - Example: Creating a post record
    - Example: Updating a profile
    - Example: Deleting a record
    - Include expected output for each example
    - _Requirements: 8.1, 8.2, 8.3_

  - [ ] 22.2 Create authentication API examples
    - Example: Creating a session
    - Example: Refreshing a token
    - Example: Using DPoP proofs
    - Include expected output for each example
    - _Requirements: 8.1, 8.2, 8.3_

  - [ ] 22.3 Create WebSocket subscription examples
    - Example: Subscribing to repo events
    - Example: Handling commit events
    - Example: Managing cursors
    - Include expected output for each example
    - _Requirements: 8.1, 8.2, 8.3_

  - [ ] 22.4 Validate all code examples compile
    - Extract and compile all examples
    - Verify zero compilation errors
    - _Requirements: 8.5, 8.6_

- [ ] 23. Update root documentation files
  - [ ] 23.1 Update README.md
    - Add clear navigation to docs/ structure
    - Update quick start section
    - Add links to deployment guides
    - Preserve existing critical information
    - _Requirements: 2.3, 2.4, 13.1, 13.4, 13.5_

  - [ ] 23.2 Update AGENTS.md
    - Update documentation references to docs/ structure
    - Update project status section
    - Add links to new guides
    - Preserve existing critical information
    - _Requirements: 2.3, 13.2, 13.4, 13.5_

  - [ ] 23.3 Verify CLAUDE.md is current
    - Review AI assistant guidance
    - Update if necessary
    - _Requirements: 13.3_

  - [ ] 23.4 Write property test for critical information preservation
    - **Property 25: Critical Information Preservation**
    - **Validates: Requirements 13.4**

- [ ] 24. Organize skills documentation
  - [ ] 24.1 Create skills index
    - Create skills/README.md with categorized skill list
    - Categorize as audit skills vs tool skills
    - Include brief description for each skill
    - _Requirements: 12.1, 12.2, 12.3_

  - [ ] 24.2 Verify skill documentation structure
    - Verify each skill has purpose, usage, examples sections
    - Update skills missing required sections
    - _Requirements: 12.4_

  - [ ] 24.3 Add cross-references to skills
    - Add skill references from relevant documentation sections
    - Link from OAuth2 docs to oauth-dpop-conformance-audit skill
    - Link from testing docs to test-gap-mapper skill
    - Link from concurrency docs to reentrancy-audit and concurrency-bug-audit skills
    - _Requirements: 12.5_

  - [ ] 24.4 Write property test for skills index completeness
    - **Property 23: Skills Index Completeness**
    - **Validates: Requirements 12.3**

  - [ ] 24.5 Write property test for skill documentation structure
    - **Property 12: Skill Documentation Structure**
    - **Validates: Requirements 12.4**

  - [ ] 24.6 Write property test for skill cross-reference presence
    - **Property 24: Skill Cross-Reference Presence**
    - **Validates: Requirements 12.5**

- [ ] 25. Create documentation index and glossary
  - [ ] 25.1 Create documentation index
    - Create docs/INDEX.md with all major topics
    - Organize hierarchically by category
    - Include brief description for each section
    - _Requirements: 15.1, 15.2_

  - [ ] 25.2 Create glossary
    - Create docs/GLOSSARY.md with technical terms
    - Include acronyms and abbreviations
    - Provide clear definitions
    - _Requirements: 15.5_

  - [ ] 25.3 Add cross-references between related docs
    - Link deployment guide to performance guide
    - Link troubleshooting guide to relevant architecture docs
    - Link API docs to code examples
    - _Requirements: 15.4_

  - [ ] 25.4 Write property test for documentation index completeness
    - **Property 29: Documentation Index Completeness**
    - **Validates: Requirements 15.1**

  - [ ] 25.5 Write property test for related documentation cross-references
    - **Property 31: Related Documentation Cross-References**
    - **Validates: Requirements 15.4**

- [ ] 26. Implement CI/CD integration
  - [ ] 26.1 Create documentation validation workflow
    - Create GitHub Actions workflow for doc validation
    - Run on all PRs that modify documentation
    - Fail build on validation errors
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

  - [ ] 26.2 Add pre-commit hook for documentation
    - Create pre-commit hook script
    - Run Markdown linting
    - Run link validation on changed files
    - _Requirements: 11.1, 11.2_

  - [ ] 26.3 Create periodic validation job
    - Create scheduled workflow for full validation
    - Run weekly on entire documentation set
    - Report results to maintainers
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 27. Create maintenance documentation
  - [ ] 27.1 Document archive management process
    - Document how to identify outdated documentation
    - Document archival procedure
    - Document quarterly review process
    - _Requirements: 10.1, 10.2, 10.3, 10.5_

  - [ ] 27.2 Document validation tool usage
    - Document how to run validation locally
    - Document how to interpret validation reports
    - Document how to fix common validation errors
    - _Requirements: 11.6_

  - [ ] 27.3 Document migration tool usage
    - Document how to configure migrations
    - Document how to execute migrations safely
    - Document rollback procedures
    - _Requirements: 14.1, 14.6_

- [ ] 28. Final validation and cleanup
  - [ ] 28.1 Run full validation suite
    - Run all validators on complete documentation set
    - Generate comprehensive validation report
    - Fix any remaining issues
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

  - [ ] 28.2 Verify all requirements covered
    - Cross-check all requirements against implementation
    - Verify all acceptance criteria met
    - Document any deviations or limitations
    - _Requirements: All_

  - [ ] 28.3 Generate final migration report
    - Document all files moved
    - Document all links updated
    - Document validation results
    - _Requirements: 14.5_

  - [ ] 28.4 Run full property-based test suite
    - Execute all property tests with 100+ iterations
    - Verify all properties hold
    - _Requirements: All_

- [ ] 29. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- All code examples and scripts use JavaScript/Node.js
- Migration tool preserves git history using git mv commands
- Validation tools integrate into CI/CD pipeline for continuous quality assurance

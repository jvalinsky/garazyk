# Requirements Document

## Introduction

This document specifies requirements for reorganizing the September PDS documentation structure to separate production-ready user documentation from historical reports, troubleshooting logs, and planning documents. The current docs/ directory contains a clean VitePress structure (sections 01-12) alongside numerous report files and legacy directories that clutter the main documentation. This reorganization will create a clear separation between user-facing documentation and archived historical materials while preserving all valuable information.

## Glossary

- **VitePress_Structure**: The production-ready documentation organized in numbered sections (01-getting-started through 12-diagrams)
- **Archive_System**: The organizational structure for historical documents including reports, troubleshooting logs, and planning materials
- **Report_File**: Documents with names ending in _REPORT.md, _SUMMARY.md, or similar patterns that document completed work
- **Troubleshooting_Log**: Documents that record debugging sessions, issue investigations, or problem resolution
- **Planning_Document**: Documents that outline future work, roadmaps, or architectural plans
- **User_Documentation**: Production-ready documentation intended for end users, developers integrating with September PDS, and operators
- **Historical_Document**: Completed reports, logs, and plans that provide valuable context but are not part of active documentation
- **Migration_Artifact**: Files created during the VitePress migration process that are no longer needed for production
- **Legacy_Directory**: Existing directories (architecture/, plans/, session-reports/, security/reports/) that contain historical materials

## Requirements

### Requirement 1: Identify Documentation Categories

**User Story:** As a documentation maintainer, I want to categorize all files in docs/ by their purpose, so that I can determine which files belong in production documentation versus archives

#### Acceptance Criteria

1. THE Archive_System SHALL categorize files into User_Documentation, Report_File, Troubleshooting_Log, Planning_Document, and Migration_Artifact
2. WHEN analyzing a file, THE Archive_System SHALL examine file name patterns, content structure, and location to determine category
3. THE Archive_System SHALL identify all files matching patterns *_REPORT.md, *_SUMMARY.md, *_VERIFICATION*.md, *_VALIDATION*.md as Report_File
4. THE Archive_System SHALL identify files in session-reports/, plans/, and security/reports/ as Historical_Document
5. THE Archive_System SHALL preserve the VitePress_Structure (01-12 directories) as User_Documentation

### Requirement 2: Create Archive Directory Structure

**User Story:** As a documentation maintainer, I want a clear organizational structure for archived materials, so that historical documents remain accessible and well-organized

#### Acceptance Criteria

1. THE Archive_System SHALL create a docs/appendices/ directory structure with subdirectories for different archive types
2. THE Archive_System SHALL organize archives into subdirectories: reports/, troubleshooting/, planning/, migration-artifacts/, and legacy-architecture/
3. WHEN creating archive subdirectories, THE Archive_System SHALL include README.md files explaining the contents and purpose
4. THE Archive_System SHALL maintain chronological organization within archive subdirectories where dates are available
5. THE Archive_System SHALL preserve original file names when moving files to archives

### Requirement 3: Move Report Files to Archives

**User Story:** As a documentation user, I want report files moved out of the main docs/ directory, so that I can focus on production documentation without clutter

#### Acceptance Criteria

1. WHEN a file matches Report_File patterns, THE Archive_System SHALL move it to docs/appendices/reports/
2. THE Archive_System SHALL move files including CLEANUP_REPORT.md, DEPLOYMENT_SUMMARY.md, FINAL_CHECKPOINT_REPORT.md, CONTENT_QUALITY_REPORT.md to archives
3. THE Archive_System SHALL move DEPLOYMENT_VERIFICATION_REPORT.md, DOCUMENTATION_ACCURACY_REVIEW.md, SITE_ACCESSIBILITY_VERIFICATION_REPORT.md to archives
4. THE Archive_System SHALL move LINK_TESTING_REPORT.md, MIGRATION_VERIFICATION_REPORT.md, PROPERTY_BASED_TEST_REPORT.md to archives
5. THE Archive_System SHALL move PHASE_*_SUMMARY.md and TASK_*_SUMMARY.md files to archives
6. THE Archive_System SHALL move report files from .vitepress/ subdirectory (CODE_ENHANCEMENT_SUMMARY.md, PHASE_*_SUMMARY.md, etc.) to archives
7. THE Archive_System SHALL move report files from 12-diagrams/ subdirectory (PROOFREADING_REPORT.md, VERIFICATION_REPORT.md) to archives

### Requirement 4: Move Troubleshooting Logs to Archives

**User Story:** As a documentation user, I want troubleshooting logs archived separately, so that I can reference them when needed without cluttering main documentation

#### Acceptance Criteria

1. WHEN a file documents debugging or issue resolution, THE Archive_System SHALL move it to docs/appendices/troubleshooting/
2. THE Archive_System SHALL move LIBDISPATCH_CRASH_DEBUG.md to troubleshooting archives
3. THE Archive_System SHALL move troubleshooting-identity-cors-2026-03-01.md to troubleshooting archives
4. THE Archive_System SHALL move test-suite-stabilization-report-2026-03-01.md to troubleshooting archives
5. THE Archive_System SHALL move security-and-architectural-remediation-report-2026-03-02.md to troubleshooting archives
6. THE Archive_System SHALL organize troubleshooting logs by date when dates are present in filenames

### Requirement 5: Move Planning Documents to Archives

**User Story:** As a documentation user, I want planning documents consolidated in archives, so that historical plans are preserved but don't interfere with current documentation

#### Acceptance Criteria

1. WHEN a file contains roadmaps, plans, or future work proposals, THE Archive_System SHALL move it to docs/appendices/planning/
2. THE Archive_System SHALL move all files from docs/plans/ directory to docs/appendices/planning/
3. THE Archive_System SHALL move all files from docs/plan/ directory to docs/appendices/planning/
4. THE Archive_System SHALL move documentation-improvement-plan.md, totp-2fa-plan.md, next-steps.md to planning archives
5. THE Archive_System SHALL preserve the plans/archive/ subdirectory structure within the new location
6. THE Archive_System SHALL remove empty Legacy_Directory folders after moving contents

### Requirement 6: Archive Migration Artifacts

**User Story:** As a documentation maintainer, I want VitePress migration artifacts archived, so that the migration history is preserved without cluttering the production site

#### Acceptance Criteria

1. WHEN a file was created during VitePress migration and is no longer needed, THE Archive_System SHALL move it to docs/appendices/migration-artifacts/
2. THE Archive_System SHALL move migration-report.md, migration-report.json, migration-mapping.json to migration artifacts
3. THE Archive_System SHALL move MIGRATION_GUIDE.md, MIGRATION_VERIFICATION_REPORT.md to migration artifacts
4. THE Archive_System SHALL move JEKYLL_ARCHIVE.md to migration artifacts
5. THE Archive_System SHALL move URL_MAPPING.md to migration artifacts
6. THE Archive_System SHALL move git-history.json and graph-data.json to migration artifacts

### Requirement 7: Consolidate Legacy Architecture Documentation

**User Story:** As a documentation user, I want legacy architecture documents archived separately from current architecture documentation, so that I can distinguish between current and historical architectural information

#### Acceptance Criteria

1. WHEN architecture documents duplicate or supersede content in VitePress_Structure, THE Archive_System SHALL move them to docs/appendices/legacy-architecture/
2. THE Archive_System SHALL move contents of docs/architecture/ directory to legacy architecture archives
3. THE Archive_System SHALL preserve .dot diagram files in legacy architecture archives
4. THE Archive_System SHALL move atproto-plc-architecture.md to legacy architecture archives
5. THE Archive_System SHALL create a README.md in legacy-architecture/ explaining that current architecture docs are in sections 01-03
6. THE Archive_System SHALL remove the empty docs/architecture/ directory after moving contents

### Requirement 8: Archive Session Reports

**User Story:** As a documentation maintainer, I want session reports archived chronologically, so that development history is preserved but separate from user documentation

#### Acceptance Criteria

1. WHEN a file documents a development session, THE Archive_System SHALL move it to docs/appendices/reports/sessions/
2. THE Archive_System SHALL move all files from docs/session-reports/ to the sessions archive
3. THE Archive_System SHALL organize session reports chronologically by date in filename
4. THE Archive_System SHALL remove the empty docs/session-reports/ directory after moving contents

### Requirement 9: Archive Security Reports

**User Story:** As a security auditor, I want historical security reports archived separately from current security documentation, so that I can review past findings without confusion

#### Acceptance Criteria

1. WHEN security analysis documents are completed, THE Archive_System SHALL move them to docs/appendices/reports/security/
2. THE Archive_System SHALL move contents of docs/security/reports/ to security report archives
3. THE Archive_System SHALL preserve docs/security/ directory for current security documentation (README.md, guides)
4. THE Archive_System SHALL move SECURITY_ANALYSIS_REPORT.md, SQL_INJECTION_VULNERABILITY_REPORT.md to security archives
5. THE Archive_System SHALL remove the empty docs/security/reports/ directory after moving contents

### Requirement 10: Preserve Production Documentation Structure

**User Story:** As a documentation user, I want the VitePress production structure unchanged, so that I can continue accessing current documentation without disruption

#### Acceptance Criteria

1. THE Archive_System SHALL NOT modify files in directories 01-getting-started through 12-diagrams
2. THE Archive_System SHALL NOT modify index.md, README.md, SUMMARY.md, or GLOSSARY.md in docs/ root
3. THE Archive_System SHALL NOT modify docs/.vitepress/config.ts or docs/.vitepress/sidebar.ts
4. THE Archive_System SHALL NOT modify docs/templates/ directory
5. THE Archive_System SHALL NOT modify docs/guides/ directory (current operational guides)
6. THE Archive_System SHALL NOT modify docs/examples/ directory
7. THE Archive_System SHALL NOT modify docs/oauth2/ directory (current OAuth2 documentation)

### Requirement 11: Update Documentation Index

**User Story:** As a documentation user, I want the main documentation index to reference the appendices, so that I can discover archived materials when needed

#### Acceptance Criteria

1. WHEN archives are created, THE Archive_System SHALL add an "Appendices" section to the VitePress sidebar
2. THE Archive_System SHALL create docs/appendices/index.md with an overview of archived materials
3. THE Archive_System SHALL include links to major archive categories in the appendices index
4. THE Archive_System SHALL add a note in docs/README.md mentioning the appendices location
5. THE Archive_System SHALL maintain alphabetical or chronological ordering in archive indexes

### Requirement 12: Preserve File History and Links

**User Story:** As a documentation maintainer, I want file moves tracked in git, so that file history is preserved and links can be updated

#### Acceptance Criteria

1. WHEN moving files, THE Archive_System SHALL use git mv commands to preserve file history
2. THE Archive_System SHALL scan all markdown files for internal links to moved files
3. WHEN a link points to a moved file, THE Archive_System SHALL update the link to the new location
4. THE Archive_System SHALL generate a mapping file documenting old paths to new paths
5. THE Archive_System SHALL verify that no broken internal links exist after reorganization

### Requirement 13: Clean Up Build Artifacts

**User Story:** As a documentation maintainer, I want build artifacts removed from version control, so that the repository only contains source documentation

#### Acceptance Criteria

1. THE Archive_System SHALL identify docs/_site/ and docs/site/ as build output directories
2. THE Archive_System SHALL verify these directories are in .gitignore
3. IF build directories are tracked in git, THEN THE Archive_System SHALL remove them from version control
4. THE Archive_System SHALL preserve docs/.vitepress/dist/ in .gitignore as VitePress build output
5. THE Archive_System SHALL document the build output locations in docs/README.md

### Requirement 14: Document Archive Organization

**User Story:** As a future documentation maintainer, I want clear documentation of the archive structure, so that I understand where to find and place historical documents

#### Acceptance Criteria

1. THE Archive_System SHALL create docs/appendices/README.md explaining the archive organization
2. THE Archive_System SHALL document the criteria for each archive category
3. THE Archive_System SHALL provide examples of file types in each archive category
4. THE Archive_System SHALL include a decision tree for categorizing new documents
5. THE Archive_System SHALL document the process for adding new archived materials

### Requirement 15: Validate Documentation Integrity

**User Story:** As a documentation maintainer, I want validation that the reorganization is complete and correct, so that I can verify no information was lost

#### Acceptance Criteria

1. WHEN reorganization is complete, THE Archive_System SHALL generate a validation report
2. THE Archive_System SHALL verify that all files from the original docs/ structure are accounted for
3. THE Archive_System SHALL verify that no files were deleted, only moved
4. THE Archive_System SHALL verify that all internal documentation links resolve correctly
5. THE Archive_System SHALL verify that the VitePress build succeeds after reorganization
6. THE Archive_System SHALL generate a summary showing file counts before and after by category

# Design Document: Documentation Archive Reorganization

## Overview

This design specifies a TypeScript-based tool for reorganizing the September PDS documentation structure by separating production-ready user documentation from historical reports, troubleshooting logs, and planning documents. The tool will create a clean archive system under `docs/appendices/` while preserving all file history through git operations and maintaining link integrity across the documentation.

The reorganization addresses the current state where the `docs/` directory contains a clean VitePress structure (sections 01-12) alongside numerous report files, legacy directories, and migration artifacts that clutter the main documentation. By moving these materials to a well-organized archive, we improve documentation discoverability while preserving valuable historical context.

### Goals

- Separate production documentation from historical materials
- Preserve all file history using git mv operations
- Maintain link integrity by updating all internal references
- Create a discoverable archive structure with clear organization
- Validate that no files are lost and all links remain functional
- Generate comprehensive reports documenting the reorganization

### Non-Goals

- Modifying the content of any documentation files
- Changing the VitePress structure (sections 01-12)
- Removing any files from version control (only moving)
- Reorganizing current operational guides or templates

## Architecture

### System Components

The archive reorganization system consists of four main components:

1. **File Categorizer**: Analyzes files to determine their category (user documentation, report, troubleshooting log, planning document, or migration artifact)
2. **Archive Organizer**: Creates the archive directory structure and moves files to appropriate locations
3. **Link Updater**: Scans all markdown files and updates internal links to reflect new file locations
4. **Validator**: Verifies reorganization completeness and generates reports

### Component Interaction

```
┌─────────────────┐
│ File Categorizer│
│                 │
│ - Pattern match │
│ - Path analysis │
│ - Content scan  │
└────────┬────────┘
         │
         ├─> Categories
         │
         v
┌─────────────────┐
│Archive Organizer│
│                 │
│ - Create dirs   │
│ - Git mv files  │
│ - Generate map  │
└────────┬────────┘
         │
         ├─> File mapping
         │
         v
┌─────────────────┐
│  Link Updater   │
│                 │
│ - Scan markdown │
│ - Update links  │
│ - Verify refs   │
└────────┬────────┘
         │
         v
┌─────────────────┐
│   Validator     │
│                 │
│ - Check files   │
│ - Test links    │
│ - Build test    │
│ - Generate report│
└─────────────────┘
```


## Components and Interfaces

### File Categorizer

The File Categorizer analyzes files to determine their appropriate category based on file name patterns, directory location, and content structure.

#### Interface

```typescript
interface FileCategorizer {
  categorizeFile(filePath: string): FileCategory;
  categorizeAll(rootDir: string): Map<string, FileCategory>;
}

enum FileCategory {
  USER_DOCUMENTATION = 'user-documentation',
  REPORT = 'report',
  TROUBLESHOOTING = 'troubleshooting',
  PLANNING = 'planning',
  MIGRATION_ARTIFACT = 'migration-artifact',
  LEGACY_ARCHITECTURE = 'legacy-architecture',
  SESSION_REPORT = 'session-report',
  SECURITY_REPORT = 'security-report'
}

interface CategorizationRule {
  name: string;
  priority: number;
  matches(filePath: string, content?: string): boolean;
  category: FileCategory;
}
```

#### Categorization Rules

Rules are evaluated in priority order (highest first):

1. **VitePress Structure Preservation** (Priority: 100)
   - Pattern: Files in `01-getting-started/` through `12-diagrams/`
   - Category: USER_DOCUMENTATION
   - Action: Never move these files

2. **Report File Pattern** (Priority: 90)
   - Pattern: `*_REPORT.md`, `*_SUMMARY.md`, `*_VERIFICATION*.md`, `*_VALIDATION*.md`
   - Category: REPORT
   - Target: `docs/appendices/reports/`

3. **Session Reports** (Priority: 85)
   - Pattern: Files in `session-reports/` directory
   - Category: SESSION_REPORT
   - Target: `docs/appendices/reports/sessions/`

4. **Security Reports** (Priority: 85)
   - Pattern: Files in `security/reports/` directory
   - Category: SECURITY_REPORT
   - Target: `docs/appendices/reports/security/`

5. **Troubleshooting Logs** (Priority: 80)
   - Pattern: Files with `debug`, `crash`, `troubleshooting`, `stabilization` in name
   - Category: TROUBLESHOOTING
   - Target: `docs/appendices/troubleshooting/`

6. **Planning Documents** (Priority: 75)
   - Pattern: Files in `plans/` or `plan/` directories, or files with `plan`, `roadmap`, `next-steps` in name
   - Category: PLANNING
   - Target: `docs/appendices/planning/`

7. **Migration Artifacts** (Priority: 70)
   - Pattern: Files with `migration`, `jekyll`, `url-mapping`, `git-history`, `graph-data` in name
   - Category: MIGRATION_ARTIFACT
   - Target: `docs/appendices/migration-artifacts/`

8. **Legacy Architecture** (Priority: 65)
   - Pattern: Files in `architecture/` directory
   - Category: LEGACY_ARCHITECTURE
   - Target: `docs/appendices/legacy-architecture/`

9. **Protected Directories** (Priority: 60)
   - Pattern: Files in `templates/`, `guides/`, `oauth2/`, `examples/`
   - Category: USER_DOCUMENTATION
   - Action: Never move these files

10. **Root Documentation Files** (Priority: 50)
    - Pattern: `index.md`, `README.md`, `SUMMARY.md`, `GLOSSARY.md` in docs root
    - Category: USER_DOCUMENTATION
    - Action: Never move these files


### Archive Organizer

The Archive Organizer creates the archive directory structure and moves files using git operations to preserve history.

#### Interface

```typescript
interface ArchiveOrganizer {
  createArchiveStructure(): void;
  moveFile(sourcePath: string, category: FileCategory): MoveResult;
  moveAll(fileMap: Map<string, FileCategory>): MoveResult[];
  generateMapping(): FileMapping;
}

interface MoveResult {
  success: boolean;
  sourcePath: string;
  targetPath: string;
  gitCommand: string;
  error?: string;
}

interface FileMapping {
  timestamp: string;
  moves: Array<{
    oldPath: string;
    newPath: string;
    category: FileCategory;
  }>;
}
```

#### Archive Directory Structure

```
docs/appendices/
├── README.md                          # Overview of archive organization
├── index.md                           # VitePress-compatible index
├── reports/                           # Completed reports
│   ├── README.md
│   ├── sessions/                      # Development session reports
│   │   ├── README.md
│   │   └── *.md
│   ├── security/                      # Security analysis reports
│   │   ├── README.md
│   │   └── *.md
│   └── *.md                           # General reports
├── troubleshooting/                   # Debugging and issue resolution
│   ├── README.md
│   └── *.md
├── planning/                          # Historical plans and roadmaps
│   ├── README.md
│   ├── archive/                       # Preserved subdirectory structure
│   │   └── *.md
│   └── *.md
├── migration-artifacts/               # VitePress migration materials
│   ├── README.md
│   └── *.md, *.json
└── legacy-architecture/               # Superseded architecture docs
    ├── README.md
    └── *.md, *.dot
```

#### Git Operations

All file moves use `git mv` to preserve history:

```bash
git mv <source> <target>
```

The tool executes git commands via Node.js child_process:

```typescript
import { execSync } from 'child_process';

function gitMoveFile(source: string, target: string): void {
  const command = `git mv "${source}" "${target}"`;
  execSync(command, { cwd: docsRoot });
}
```


### Link Updater

The Link Updater scans all markdown files and updates internal links to reflect new file locations.

#### Interface

```typescript
interface LinkUpdater {
  scanLinks(filePath: string): LinkReference[];
  updateLinks(filePath: string, mapping: FileMapping): LinkUpdateResult;
  updateAllLinks(mapping: FileMapping): LinkUpdateResult[];
}

interface LinkReference {
  filePath: string;
  lineNumber: number;
  linkText: string;
  linkTarget: string;
  isInternal: boolean;
}

interface LinkUpdateResult {
  filePath: string;
  linksUpdated: number;
  updates: Array<{
    line: number;
    oldTarget: string;
    newTarget: string;
  }>;
}
```

#### Link Detection

The tool uses regex patterns to find markdown links:

```typescript
// Match markdown links: [text](url)
const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;

// Match relative links (not external URLs)
function isInternalLink(url: string): boolean {
  return !url.startsWith('http://') && 
         !url.startsWith('https://') &&
         !url.startsWith('#');
}
```

#### Link Update Strategy

1. **Build Path Mapping**: Create a map of old paths to new paths from the file mapping
2. **Scan All Markdown**: Find all markdown files in docs/ (including archives)
3. **Extract Links**: Parse each file to find internal links
4. **Resolve Targets**: Resolve relative links to absolute paths
5. **Check Mapping**: If target path is in the mapping, update the link
6. **Update Relative Path**: Calculate new relative path from link source to new target
7. **Write Updated Content**: Write the file with updated links

#### Path Resolution

```typescript
function resolveRelativeLink(fromFile: string, linkTarget: string): string {
  const fromDir = path.dirname(fromFile);
  const absoluteTarget = path.resolve(fromDir, linkTarget);
  return absoluteTarget;
}

function calculateNewRelativePath(fromFile: string, toFile: string): string {
  const fromDir = path.dirname(fromFile);
  const relativePath = path.relative(fromDir, toFile);
  return relativePath;
}
```


### Validator

The Validator verifies reorganization completeness and generates comprehensive reports.

#### Interface

```typescript
interface Validator {
  validateFileIntegrity(): ValidationResult;
  validateLinks(): ValidationResult;
  validateVitePressConfig(): ValidationResult;
  validateBuild(): ValidationResult;
  generateReport(): ValidationReport;
}

interface ValidationResult {
  passed: boolean;
  errors: ValidationError[];
  warnings: string[];
}

interface ValidationError {
  type: 'missing-file' | 'broken-link' | 'config-error' | 'build-error';
  message: string;
  details?: any;
}

interface ValidationReport {
  timestamp: string;
  summary: {
    filesProcessed: number;
    filesMoved: number;
    linksUpdated: number;
    categoryCounts: Record<FileCategory, number>;
  };
  validation: {
    fileIntegrity: ValidationResult;
    linkIntegrity: ValidationResult;
    configIntegrity: ValidationResult;
    buildSuccess: ValidationResult;
  };
  fileMapping: FileMapping;
}
```

#### Validation Checks

1. **File Integrity**
   - Count all files before reorganization
   - Count all files after reorganization
   - Verify counts match (no files lost)
   - Generate checksums for critical files
   - Verify checksums match after moves

2. **Link Integrity**
   - Scan all markdown files for links
   - Resolve each link target
   - Verify target exists
   - Report any broken links

3. **VitePress Config**
   - Verify sidebar.ts includes appendices section
   - Verify appendices/index.md exists
   - Check that config.ts is valid TypeScript

4. **Build Success**
   - Execute `npm run docs:build` in docs/
   - Capture exit code
   - Report build success or failure
   - Capture any build errors


## Data Models

### File Category Enumeration

```typescript
enum FileCategory {
  USER_DOCUMENTATION = 'user-documentation',
  REPORT = 'report',
  TROUBLESHOOTING = 'troubleshooting',
  PLANNING = 'planning',
  MIGRATION_ARTIFACT = 'migration-artifact',
  LEGACY_ARCHITECTURE = 'legacy-architecture',
  SESSION_REPORT = 'session-report',
  SECURITY_REPORT = 'security-report'
}
```

### File Information

```typescript
interface FileInfo {
  path: string;              // Absolute path
  relativePath: string;      // Relative to docs/
  category: FileCategory;
  size: number;
  checksum: string;          // SHA-256 hash
  lastModified: Date;
}
```

### Categorization Rule

```typescript
interface CategorizationRule {
  name: string;
  priority: number;
  matches(filePath: string, content?: string): boolean;
  category: FileCategory;
  targetDirectory: string;
}
```

### File Mapping

```typescript
interface FileMapping {
  timestamp: string;
  moves: Array<{
    oldPath: string;
    newPath: string;
    category: FileCategory;
    checksum: string;
  }>;
}
```

### Link Reference

```typescript
interface LinkReference {
  sourceFile: string;        // File containing the link
  lineNumber: number;
  columnNumber: number;
  linkText: string;          // Display text
  linkTarget: string;        // Original target
  resolvedTarget: string;    // Absolute path
  isInternal: boolean;
  isValid: boolean;
}
```

### Validation Report

```typescript
interface ValidationReport {
  timestamp: string;
  summary: {
    filesProcessed: number;
    filesMoved: number;
    linksUpdated: number;
    categoryCounts: Record<FileCategory, number>;
  };
  validation: {
    fileIntegrity: ValidationResult;
    linkIntegrity: ValidationResult;
    configIntegrity: ValidationResult;
    buildSuccess: ValidationResult;
  };
  fileMapping: FileMapping;
  errors: ValidationError[];
  warnings: string[];
}
```


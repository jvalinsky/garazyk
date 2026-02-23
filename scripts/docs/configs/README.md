# Migration Configuration Files

This directory contains migration configuration files for the documentation consolidation tool.

## Configuration Format

Migration configurations are JSON files that define how to move documentation files from source directories to destination directories while preserving git history and updating cross-references.

### Schema

```json
{
  "version": "1.0.0",
  "description": "Optional description of this migration",
  "migrations": [
    {
      "source": "source/directory",
      "destination": "destination/directory",
      "filePatterns": ["**/*.md", "**/*.txt"],
      "excludePatterns": ["**/.git/**", "**/node_modules/**"],
      "preserveStructure": true,
      "updateReferences": true,
      "removeEmptyDirs": true
    }
  ],
  "options": {
    "dryRun": false,
    "verbose": false,
    "generateReport": true,
    "reportPath": "migration-report.json",
    "mappingPath": "migration-mapping.json",
    "continueOnError": false
  }
}
```

### Required Fields

- `version` (string): Semantic version of the configuration format (e.g., "1.0.0")
- `migrations` (array): Array of migration operations (must have at least one)
  - `source` (string): Source directory path (relative to repository root)
  - `destination` (string): Destination directory path (relative to repository root)

### Optional Fields

#### Migration Options

- `filePatterns` (array of strings): Glob patterns for files to include
  - Default: `["**/*"]` (all files)
  - Example: `["**/*.md", "**/*.txt", "**/*.json"]`

- `excludePatterns` (array of strings): Glob patterns for files to exclude
  - Default: `["**/.git/**", "**/node_modules/**", "**/.DS_Store", "**/Thumbs.db"]`
  - Example: `["**/*.swp", "**/*~"]`

- `preserveStructure` (boolean): Whether to preserve directory structure from source
  - Default: `true`
  - If `true`, files maintain their relative paths from source to destination
  - If `false`, all files are moved to the root of the destination directory

- `updateReferences` (boolean): Whether to update cross-references in moved files
  - Default: `true`
  - Updates Markdown links, relative paths, and cross-references to reflect new locations

- `removeEmptyDirs` (boolean): Whether to remove empty source directories after migration
  - Default: `true`
  - Recursively removes directories that become empty after files are moved

#### Global Options

- `dryRun` (boolean): Perform a dry run without making actual changes
  - Default: `false`
  - When `true`, shows what would be done without modifying files

- `verbose` (boolean): Enable verbose logging
  - Default: `false`
  - When `true`, outputs detailed information about each operation

- `generateReport` (boolean): Generate a migration report file
  - Default: `true`
  - Creates a JSON report with statistics and details of the migration

- `reportPath` (string): Path for the migration report file
  - Default: `"migration-report.json"`
  - Relative to repository root

- `mappingPath` (string): Path for the migration mapping file
  - Default: `"migration-mapping.json"`
  - Contains old path → new path mappings for all moved files

- `continueOnError` (boolean): Continue migration even if some files fail
  - Default: `false`
  - When `true`, logs errors but continues with remaining files
  - When `false`, stops migration on first error

## Validation Rules

The configuration validator enforces these rules:

1. **Version Format**: Must be a valid semantic version (e.g., "1.0.0")
2. **Non-Empty Migrations**: Must have at least one migration operation
3. **Required Fields**: Each migration must have `source` and `destination`
4. **No Self-Migration**: Source and destination cannot be the same
5. **No Nested Paths**: Destination cannot be inside source (or vice versa)
6. **No Duplicate Sources**: Each source directory can only appear once
7. **No Extra Properties**: Unknown properties are rejected

## Example Configurations

### Basic Migration

Minimal configuration to move files from one directory to another:

```json
{
  "version": "1.0.0",
  "migrations": [
    {
      "source": "old-docs",
      "destination": "docs"
    }
  ]
}
```

### Multiple Source Consolidation

Consolidate multiple source directories into one destination:

```json
{
  "version": "1.0.0",
  "description": "Consolidate plan/ and plans/ into docs/plans/",
  "migrations": [
    {
      "source": "plan",
      "destination": "docs/plans"
    },
    {
      "source": "plans",
      "destination": "docs/plans"
    }
  ]
}
```

### Selective File Migration

Move only specific file types:

```json
{
  "version": "1.0.0",
  "migrations": [
    {
      "source": "old-docs",
      "destination": "docs",
      "filePatterns": ["**/*.md", "**/*.txt"],
      "excludePatterns": ["**/draft-*.md", "**/.DS_Store"]
    }
  ]
}
```

### Dry Run Configuration

Test migration without making changes:

```json
{
  "version": "1.0.0",
  "migrations": [
    {
      "source": "plan",
      "destination": "docs/plans"
    }
  ],
  "options": {
    "dryRun": true,
    "verbose": true
  }
}
```

## Usage

To use a migration configuration:

```bash
# Run migration with a config file
node migrate.js configs/plan-consolidation.json

# Dry run to preview changes
node migrate.js configs/plan-consolidation.json --dry-run

# Verbose output
node migrate.js configs/plan-consolidation.json --verbose
```

## Available Configurations

- `plan-consolidation.json`: Consolidates `plan/` and `plans/` directories into `docs/plans/`

## Creating New Configurations

1. Copy an existing configuration as a template
2. Update the `source` and `destination` paths
3. Adjust `filePatterns` and `excludePatterns` as needed
4. Test with `dryRun: true` first
5. Validate the configuration:

```bash
node -e "import('./lib/migration-schema.js').then(m => m.loadMigrationConfig('configs/your-config.json').then(c => console.log('Valid!'), e => console.error(e.message)))"
```

## Troubleshooting

### Configuration Validation Errors

If you see validation errors:

1. Check that all required fields are present (`version`, `migrations`, `source`, `destination`)
2. Verify the version format is semantic versioning (e.g., "1.0.0")
3. Ensure source and destination are different
4. Check that destination is not inside source (or vice versa)
5. Verify no duplicate source directories

### Common Mistakes

- **Missing quotes**: JSON requires double quotes for strings
- **Trailing commas**: JSON does not allow trailing commas in arrays/objects
- **Invalid paths**: Use forward slashes (`/`) even on Windows
- **Absolute paths**: Use relative paths from repository root, not absolute paths

## Schema Reference

For the complete JSON schema definition, see `lib/migration-schema.js`.

The schema is validated using a custom validator that checks:
- Type correctness (string, boolean, array, object)
- Required properties
- String patterns (e.g., semantic version format)
- Array constraints (minimum items)
- Semantic rules (no nested paths, no duplicates)

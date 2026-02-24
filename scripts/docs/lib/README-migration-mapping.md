# Migration Mapping Generator

The migration mapping generator creates a JSON file that documents all file moves during documentation consolidation. This provides an audit trail and reference for the migration, including file metadata such as size, last modified timestamp, and git commit hash.

## Purpose

When consolidating documentation from multiple directories (e.g., `plan/` and `plans/`) into a unified structure (`docs/`), it's important to maintain a record of:

- Which files were moved where
- File metadata at the time of migration
- Git history information for each file

This mapping file serves as:
- An audit trail for the migration
- A reference for updating cross-references and links
- Documentation for future maintainers

## Features

- **File Metadata Capture**: Records file size, last modified timestamp, and git commit hash
- **Batch Processing**: Generates mappings for multiple files efficiently
- **Error Handling**: Gracefully handles non-existent files and missing git history
- **Bidirectional Lookup**: Find new path from old path or vice versa
- **JSON Output**: Structured, human-readable format

## API Reference

### `generateMappingEntry(oldPath, newPath, repoRoot)`

Generates a migration mapping entry for a single file.

**Parameters:**
- `oldPath` (string): Original file path (relative to repo root)
- `newPath` (string): New file path (relative to repo root)
- `repoRoot` (string): Repository root directory (default: `process.cwd()`)

**Returns:** Promise<Object> - Mapping entry with metadata

**Example:**
```javascript
const entry = await generateMappingEntry(
  'plan/oauth2.md',
  'docs/plans/oauth2.md',
  '/path/to/repo'
);

console.log(entry);
// {
//   oldPath: 'plan/oauth2.md',
//   newPath: 'docs/plans/oauth2.md',
//   size: 12345,
//   lastModified: '2024-01-15T10:30:00.000Z',
//   gitCommit: 'abc123def456...'
// }
```

### `generateMigrationMapping(fileList, repoRoot)`

Generates a complete migration mapping from a file list.

**Parameters:**
- `fileList` (Array<Object>): Array of `{source, destination}` objects
- `repoRoot` (string): Repository root directory (default: `process.cwd()`)

**Returns:** Promise<Object> - Migration mapping object

**Example:**
```javascript
const fileList = [
  { source: 'plan/oauth2.md', destination: 'docs/plans/oauth2.md' },
  { source: 'plan/sync.md', destination: 'docs/plans/sync.md' }
];

const mapping = await generateMigrationMapping(fileList, '/path/to/repo');

console.log(mapping);
// {
//   version: '1.0.0',
//   generatedAt: '2024-01-15T10:30:00.000Z',
//   repoRoot: '/path/to/repo',
//   totalFiles: 2,
//   successfulMappings: 2,
//   failedMappings: 0,
//   mappings: [ ... ]
// }
```

### `writeMigrationMapping(mapping, outputPath)`

Writes migration mapping to a JSON file.

**Parameters:**
- `mapping` (Object): Migration mapping object
- `outputPath` (string): Output file path

**Returns:** Promise<void>

**Example:**
```javascript
await writeMigrationMapping(mapping, 'migration-mapping.json');
```

### `generateAndWriteMapping(fileList, outputPath, options)`

Generates and writes migration mapping in one operation.

**Parameters:**
- `fileList` (Array<Object>): Array of `{source, destination}` objects
- `outputPath` (string): Output file path
- `options` (Object): Options
  - `repoRoot` (string): Repository root directory

**Returns:** Promise<Object> - Generated migration mapping

**Example:**
```javascript
const mapping = await generateAndWriteMapping(
  fileList,
  'migration-mapping.json',
  { repoRoot: '/path/to/repo' }
);
```

### `readMigrationMapping(mappingPath)`

Reads a migration mapping from a JSON file.

**Parameters:**
- `mappingPath` (string): Path to mapping file

**Returns:** Promise<Object> - Migration mapping object

**Example:**
```javascript
const mapping = await readMigrationMapping('migration-mapping.json');
```

### `lookupNewPath(mapping, oldPath)`

Looks up the new path for an old path in a migration mapping.

**Parameters:**
- `mapping` (Object): Migration mapping object
- `oldPath` (string): Old file path to look up

**Returns:** string|null - New path or null if not found

**Example:**
```javascript
const newPath = lookupNewPath(mapping, 'plan/oauth2.md');
console.log(newPath); // 'docs/plans/oauth2.md'
```

### `lookupOldPath(mapping, newPath)`

Looks up the old path for a new path in a migration mapping.

**Parameters:**
- `mapping` (Object): Migration mapping object
- `newPath` (string): New file path to look up

**Returns:** string|null - Old path or null if not found

**Example:**
```javascript
const oldPath = lookupOldPath(mapping, 'docs/plans/oauth2.md');
console.log(oldPath); // 'plan/oauth2.md'
```

## Mapping File Format

The migration mapping file is a JSON file with the following structure:

```json
{
  "version": "1.0.0",
  "generatedAt": "2024-01-15T10:30:00.000Z",
  "repoRoot": "/path/to/repo",
  "totalFiles": 3,
  "successfulMappings": 3,
  "failedMappings": 0,
  "mappings": [
    {
      "oldPath": "plan/oauth2-implementation.md",
      "newPath": "docs/plans/oauth2-implementation.md",
      "size": 12345,
      "lastModified": "2024-01-10T15:20:00.000Z",
      "gitCommit": "abc123def456789..."
    },
    {
      "oldPath": "plan/repository-sync.md",
      "newPath": "docs/plans/repository-sync.md",
      "size": 8765,
      "lastModified": "2024-01-12T09:15:00.000Z",
      "gitCommit": "def456abc123789..."
    }
  ]
}
```

### Field Descriptions

- `version`: Semantic version of the mapping format
- `generatedAt`: ISO 8601 timestamp when mapping was generated
- `repoRoot`: Absolute path to repository root
- `totalFiles`: Total number of files in the file list
- `successfulMappings`: Number of successfully mapped files
- `failedMappings`: Number of failed mappings
- `mappings`: Array of mapping entries
  - `oldPath`: Original file path (relative to repo root)
  - `newPath`: New file path (relative to repo root)
  - `size`: File size in bytes (null if file doesn't exist)
  - `lastModified`: ISO 8601 timestamp of last modification (null if file doesn't exist)
  - `gitCommit`: Git commit hash (40-character SHA-1, null if no git history)
- `errors`: Array of error objects (only present if there are errors)

## Usage Examples

### Basic Usage

```javascript
import { generateAndWriteMapping } from './lib/migration-mapping.js';

const fileList = [
  { source: 'plan/oauth2.md', destination: 'docs/plans/oauth2.md' },
  { source: 'plan/sync.md', destination: 'docs/plans/sync.md' },
  { source: 'plans/deploy.md', destination: 'docs/guides/deployment.md' }
];

const mapping = await generateAndWriteMapping(
  fileList,
  'migration-mapping.json'
);

console.log(`Mapped ${mapping.successfulMappings} files`);
```

### Reading and Using Mapping

```javascript
import { readMigrationMapping, lookupNewPath } from './lib/migration-mapping.js';

const mapping = await readMigrationMapping('migration-mapping.json');

// Find new location for a file
const newPath = lookupNewPath(mapping, 'plan/oauth2.md');
console.log(`File moved to: ${newPath}`);

// Iterate over all mappings
mapping.mappings.forEach((entry) => {
  console.log(`${entry.oldPath} → ${entry.newPath}`);
  console.log(`  Size: ${entry.size} bytes`);
  console.log(`  Commit: ${entry.gitCommit?.substring(0, 8)}`);
});
```

### Integration with Migration Tool

```javascript
import { batchGitMv } from './lib/git-operations.js';
import { generateAndWriteMapping } from './lib/migration-mapping.js';

// Define files to migrate
const fileList = [
  { source: 'plan/oauth2.md', destination: 'docs/plans/oauth2.md' },
  { source: 'plan/sync.md', destination: 'docs/plans/sync.md' }
];

// Generate mapping BEFORE migration (to capture original metadata)
const mapping = await generateAndWriteMapping(
  fileList,
  'migration-mapping.json'
);

// Perform migration
const result = await batchGitMv(fileList, {
  repoRoot: process.cwd()
});

console.log(`Migration complete: ${result.summary.success} files moved`);
console.log(`Mapping saved to: migration-mapping.json`);
```

## Error Handling

The migration mapping generator handles errors gracefully:

### Non-existent Files

If a source file doesn't exist, the mapping entry will include null values for metadata:

```json
{
  "oldPath": "nonexistent.md",
  "newPath": "docs/nonexistent.md",
  "size": null,
  "lastModified": null,
  "gitCommit": null,
  "error": "ENOENT: no such file or directory"
}
```

### Files Without Git History

If a file exists but has no git history (untracked file), the `gitCommit` field will be null:

```json
{
  "oldPath": "untracked.md",
  "newPath": "docs/untracked.md",
  "size": 1234,
  "lastModified": "2024-01-15T10:30:00.000Z",
  "gitCommit": null
}
```

### Invalid File Entries

Invalid entries in the file list are reported in the `errors` array:

```json
{
  "totalFiles": 3,
  "successfulMappings": 1,
  "failedMappings": 2,
  "mappings": [ ... ],
  "errors": [
    {
      "file": { "source": "file.md" },
      "error": "Invalid file entry: must have source and destination properties"
    },
    {
      "file": null,
      "error": "Invalid file entry: must be an object"
    }
  ]
}
```

## Testing

The module includes comprehensive unit tests covering:

- Metadata capture for tracked files
- Handling of non-existent files
- Files without git history
- Batch mapping generation
- File I/O operations
- Lookup functions
- Error conditions

Run tests:
```bash
node scripts/docs/lib/migration-mapping.test.js
```

## Integration with Other Modules

The migration mapping generator integrates with:

- **git-operations.js**: Use mapping to track files before/after git mv operations
- **content-updater.js**: Use mapping to update cross-references in moved files
- **link-parser.js**: Use mapping to resolve old links to new locations
- **path-resolver.js**: Use mapping to calculate new relative paths

## Best Practices

1. **Generate mapping BEFORE migration**: Capture metadata from original file locations
2. **Commit mapping file**: Include in version control for audit trail
3. **Use for link updates**: Reference mapping when updating cross-references
4. **Validate completeness**: Check that all expected files are in the mapping
5. **Archive old mapping**: Keep historical mappings for reference

## See Also

- [Git Operations](./README-git-operations.md) - Git mv operations for history preservation
- [Content Updater](./README-content-updater.md) - Update cross-references using mapping
- [Link Parser](./README-link-parser.md) - Parse links for updating
- [Path Resolver](./README-path-resolver.md) - Calculate new relative paths

# Git Operations Module

This module provides functions for executing git mv operations with history preservation, batch processing, and rollback capabilities. It's designed for safe documentation migration workflows.

## Features

- **History Preservation**: Uses `git mv` to maintain file history across moves
- **Batch Processing**: Move multiple files efficiently with progress tracking
- **Dry Run Mode**: Preview changes without making actual modifications
- **Error Handling**: Comprehensive error handling with rollback on failure
- **Rollback Support**: Automatically revert changes if batch operation fails
- **History Verification**: Verify that git history is preserved after moves

## Installation

```bash
npm install fs-extra
```

## API Reference

### `isGitRepository(dirPath)`

Checks if a directory is a git repository.

**Parameters:**
- `dirPath` (string): Directory path to check (default: `process.cwd()`)

**Returns:** `boolean` - True if directory is a git repository

**Example:**
```javascript
import { isGitRepository } from './lib/git-operations.js';

if (isGitRepository()) {
  console.log('Current directory is a git repository');
}
```

### `isFileTracked(filePath, repoRoot)`

Checks if a file is tracked by git.

**Parameters:**
- `filePath` (string): File path relative to repo root
- `repoRoot` (string): Repository root directory (default: `process.cwd()`)

**Returns:** `boolean` - True if file is tracked by git

**Example:**
```javascript
import { isFileTracked } from './lib/git-operations.js';

if (isFileTracked('docs/guide.md')) {
  console.log('File is tracked by git');
}
```

### `executeGitMv(sourcePath, destPath, options)`

Executes a single git mv operation.

**Parameters:**
- `sourcePath` (string): Source file path (relative to repo root)
- `destPath` (string): Destination file path (relative to repo root)
- `options` (object):
  - `repoRoot` (string): Repository root directory (default: `process.cwd()`)
  - `force` (boolean): Force move even if destination exists (default: `false`)
  - `dryRun` (boolean): Perform dry run without actual changes (default: `false`)
  - `verbose` (boolean): Enable verbose output (default: `false`)

**Returns:** `Promise<Object>` - Result object with:
- `success` (boolean): Whether operation succeeded
- `sourcePath` (string): Source file path
- `destPath` (string): Destination file path
- `message` (string): Result message
- `output` (string): Git command output (if successful)
- `dryRun` (boolean): Whether this was a dry run (if applicable)

**Throws:** `GitOperationError` - If operation fails

**Example:**
```javascript
import { executeGitMv } from './lib/git-operations.js';

try {
  const result = await executeGitMv(
    'old-docs/guide.md',
    'docs/guides/guide.md',
    { verbose: true }
  );
  
  console.log(result.message);
} catch (error) {
  console.error('Move failed:', error.message);
}
```

### `batchGitMv(fileList, options)`

Executes git mv operations for multiple files in batch.

**Parameters:**
- `fileList` (Array<Object>): Array of file move specifications:
  - `source` (string): Source file path
  - `destination` (string): Destination file path
- `options` (object):
  - `repoRoot` (string): Repository root directory (default: `process.cwd()`)
  - `force` (boolean): Force move even if destination exists (default: `false`)
  - `dryRun` (boolean): Perform dry run without actual changes (default: `false`)
  - `verbose` (boolean): Enable verbose output (default: `false`)
  - `continueOnError` (boolean): Continue processing even if some files fail (default: `false`)
  - `onProgress` (Function): Progress callback `(current, total, result) => void`

**Returns:** `Promise<Object>` - Batch result with:
- `success` (boolean): Whether all operations succeeded
- `results` (Array<Object>): Array of individual operation results
- `errors` (Array<Object>): Array of errors that occurred
- `summary` (Object): Summary statistics:
  - `total` (number): Total files processed
  - `success` (number): Successfully moved files
  - `failed` (number): Failed operations
  - `skipped` (number): Skipped files

**Throws:** `GitOperationError` - If batch operation fails (when `continueOnError` is false)

**Example:**
```javascript
import { batchGitMv } from './lib/git-operations.js';

const fileList = [
  { source: 'plan/doc1.md', destination: 'docs/doc1.md' },
  { source: 'plan/doc2.md', destination: 'docs/doc2.md' }
];

try {
  const result = await batchGitMv(fileList, {
    verbose: true,
    onProgress: (current, total, fileResult) => {
      console.log(`Progress: ${current}/${total}`);
    }
  });
  
  console.log(`Moved ${result.summary.success} files`);
} catch (error) {
  console.error('Batch operation failed:', error.message);
}
```

### `rollbackGitMv(results, options)`

Rolls back git mv operations by moving files back to their original locations.

**Parameters:**
- `results` (Array<Object>): Array of successful operation results from `executeGitMv` or `batchGitMv`
- `options` (object):
  - `repoRoot` (string): Repository root directory (default: `process.cwd()`)
  - `verbose` (boolean): Enable verbose output (default: `false`)

**Returns:** `Promise<Object>` - Rollback result with:
- `success` (boolean): Whether all rollbacks succeeded
- `rolledBack` (number): Number of operations rolled back
- `failed` (number): Number of rollback failures
- `errors` (Array<Object>): Array of rollback errors
- `message` (string): Result message (if no operations to rollback)

**Example:**
```javascript
import { batchGitMv, rollbackGitMv } from './lib/git-operations.js';

const fileList = [/* ... */];

try {
  const result = await batchGitMv(fileList);
  
  // Something went wrong, rollback
  if (!result.success) {
    await rollbackGitMv(result.results, { verbose: true });
  }
} catch (error) {
  console.error('Operation failed:', error.message);
}
```

### `verifyHistoryPreservation(filePath, options)`

Verifies that git history is preserved after a move operation.

**Parameters:**
- `filePath` (string): File path to check (relative to repo root)
- `options` (object):
  - `repoRoot` (string): Repository root directory (default: `process.cwd()`)
  - `minCommits` (number): Minimum number of commits expected in history (default: `1`)

**Returns:** `Promise<Object>` - Verification result with:
- `preserved` (boolean): Whether history is preserved
- `commitCount` (number): Number of commits found
- `history` (Array<string>): Array of commit messages (if preserved)
- `message` (string): Result message

**Example:**
```javascript
import { verifyHistoryPreservation } from './lib/git-operations.js';

const verification = await verifyHistoryPreservation('docs/guide.md', {
  minCommits: 2
});

if (verification.preserved) {
  console.log(`History preserved: ${verification.commitCount} commits`);
} else {
  console.log(`History not preserved: ${verification.message}`);
}
```

## Error Handling

The module throws `GitOperationError` for operation failures. This error includes:

- `message` (string): Error description
- `command` (string): Git command that failed (if applicable)
- `stderr` (string): Standard error output (if applicable)

**Example:**
```javascript
import { executeGitMv, GitOperationError } from './lib/git-operations.js';

try {
  await executeGitMv('source.md', 'dest.md');
} catch (error) {
  if (error instanceof GitOperationError) {
    console.error('Git operation failed:', error.message);
    if (error.command) {
      console.error('Command:', error.command);
    }
  } else {
    throw error;
  }
}
```

## Best Practices

### 1. Always Use Dry Run First

Preview changes before executing actual moves:

```javascript
// Dry run
const dryRunResult = await batchGitMv(fileList, { dryRun: true });

if (dryRunResult.success) {
  // Execute actual migration
  const result = await batchGitMv(fileList);
}
```

### 2. Verify History After Migration

Always verify that git history is preserved:

```javascript
const result = await executeGitMv('old.md', 'new.md');

const verification = await verifyHistoryPreservation('new.md');
if (!verification.preserved) {
  console.warn('Warning: History may not be preserved');
}
```

### 3. Use Progress Callbacks for Large Batches

Track progress for better user experience:

```javascript
await batchGitMv(fileList, {
  onProgress: (current, total, result) => {
    const percent = Math.round((current / total) * 100);
    console.log(`[${percent}%] ${result.message}`);
  }
});
```

### 4. Handle Errors Gracefully

Use `continueOnError` for resilient migrations:

```javascript
const result = await batchGitMv(fileList, {
  continueOnError: true
});

if (result.errors.length > 0) {
  console.log('Some files failed to move:');
  result.errors.forEach(error => {
    console.log(`  - ${error.file.source}: ${error.message}`);
  });
}
```

### 5. Commit Moves for History Preservation

Git log --follow only works after moves are committed:

```javascript
import { execSync } from 'child_process';

// Execute moves
await batchGitMv(fileList);

// Commit the moves
execSync('git commit -m "Migrate documentation files"');

// Now verify history
for (const file of fileList) {
  await verifyHistoryPreservation(file.destination);
}
```

## Complete Migration Workflow

Here's a complete example of a safe migration workflow:

```javascript
import {
  isGitRepository,
  batchGitMv,
  verifyHistoryPreservation
} from './lib/git-operations.js';

async function migrateDocumentation(fileList) {
  // 1. Verify we're in a git repository
  if (!isGitRepository()) {
    throw new Error('Not in a git repository');
  }

  // 2. Dry run to preview changes
  console.log('Running dry run...');
  const dryRunResult = await batchGitMv(fileList, {
    dryRun: true,
    verbose: true
  });

  if (!dryRunResult.success) {
    throw new Error('Dry run failed');
  }

  console.log(`Dry run successful: ${dryRunResult.summary.success} files`);

  // 3. Execute actual migration
  console.log('Executing migration...');
  const result = await batchGitMv(fileList, {
    verbose: true,
    continueOnError: false,
    onProgress: (current, total) => {
      console.log(`Progress: ${current}/${total}`);
    }
  });

  if (!result.success) {
    throw new Error('Migration failed');
  }

  console.log('Migration successful');

  // 4. Commit the changes
  console.log('Committing changes...');
  execSync('git commit -m "Migrate documentation files"');

  // 5. Verify history preservation
  console.log('Verifying history preservation...');
  for (const file of fileList) {
    const verification = await verifyHistoryPreservation(file.destination);
    if (!verification.preserved) {
      console.warn(`Warning: History not preserved for ${file.destination}`);
    }
  }

  console.log('Migration completed successfully');
}
```

## Testing

Run the test suite:

```bash
node scripts/docs/lib/git-operations.test.js
```

Run examples:

```bash
node scripts/docs/examples/git-operations-example.js <example-number>
```

## Requirements

- Node.js 18+ (for native test runner)
- Git 2.0+
- fs-extra package

## License

Part of the ATProtoPDS project.

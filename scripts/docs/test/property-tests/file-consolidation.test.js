/**
 * Property-Based Test: File Consolidation Completeness
 *
 * **Validates: Requirements 1.1**
 *
 * Property 1: File Consolidation Completeness
 * For any file in source directories (plan/ or plans/), after consolidation
 * that file should exist in the destination docs/ directory with equivalent content.
 *
 * This test generates random file sets in source directories, executes consolidation,
 * and verifies all files are present in the destination with equivalent content.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import { execSync } from 'child_process';
import fs from 'fs-extra';
import path from 'path';
import os from 'os';
import crypto from 'crypto';
import { discoverFiles } from '../../lib/file-discovery.js';
import { batchGitMv } from '../../lib/git-operations.js';

/**
 * Creates a temporary git repository for testing
 */
async function createTestRepo() {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'consolidation-test-'));

  // Initialize git repo
  execSync('git init', { cwd: tmpDir, stdio: 'pipe' });
  execSync('git config user.email "test@example.com"', { cwd: tmpDir, stdio: 'pipe' });
  execSync('git config user.name "Test User"', { cwd: tmpDir, stdio: 'pipe' });

  return tmpDir;
}

/**
 * Generates random file content
 */
function generateRandomContent(minSize = 10, maxSize = 1000) {
  const size = Math.floor(Math.random() * (maxSize - minSize + 1)) + minSize;
  return crypto.randomBytes(size).toString('hex');
}

/**
 * Generates a random file structure
 * @param {number} fileCount - Number of files to generate
 * @param {number} maxDepth - Maximum directory depth
 * @returns {Array<{path: string, content: string}>} Array of file descriptors
 */
function generateRandomFileStructure(fileCount, maxDepth = 3) {
  const files = [];
  const extensions = ['.md', '.txt', '.json', '.yaml'];

  for (let i = 0; i < fileCount; i++) {
    // Generate random directory depth
    const depth = Math.floor(Math.random() * (maxDepth + 1));
    const pathParts = [];

    for (let d = 0; d < depth; d++) {
      pathParts.push(`dir${Math.floor(Math.random() * 5)}`);
    }

    // Generate filename
    const ext = extensions[Math.floor(Math.random() * extensions.length)];
    const filename = `file${i}${ext}`;
    pathParts.push(filename);

    files.push({
      path: pathParts.join('/'),
      content: generateRandomContent()
    });
  }

  return files;
}

/**
 * Creates files in a directory and commits them to git
 */
async function createFilesInRepo(repoDir, sourceDir, files) {
  const sourcePath = path.join(repoDir, sourceDir);
  await fs.ensureDir(sourcePath);

  for (const file of files) {
    const fullPath = path.join(sourcePath, file.path);
    await fs.ensureDir(path.dirname(fullPath));
    await fs.writeFile(fullPath, file.content, 'utf8');
  }

  // Add and commit all files
  execSync(`git add "${sourceDir}"`, { cwd: repoDir, stdio: 'pipe' });
  execSync(`git commit -m "Add files to ${sourceDir}"`, { cwd: repoDir, stdio: 'pipe' });
}

/**
 * Executes consolidation from source to destination
 */
async function executeConsolidation(repoDir, sourceDir, destDir) {
  // Discover files in source directory
  const files = await discoverFiles(sourceDir, {
    filePatterns: ['**/*'],
    excludePatterns: ['**/.git/**'],
    repoRoot: repoDir
  });

  // Build file list for batch move
  const fileList = files.map((file) => ({
    source: path.join(sourceDir, file),
    destination: path.join(destDir, file)
  }));

  // Execute batch git mv
  if (fileList.length > 0) {
    await batchGitMv(fileList, {
      repoRoot: repoDir,
      continueOnError: false
    });

    // Commit the moves
    execSync(`git commit -m "Consolidate ${sourceDir} to ${destDir}"`, {
      cwd: repoDir,
      stdio: 'pipe'
    });
  }

  return files;
}

/**
 * Verifies that all source files exist in destination with equivalent content
 */
async function verifyConsolidation(repoDir, sourceFiles, destDir) {
  const results = {
    total: sourceFiles.length,
    found: 0,
    missing: [],
    contentMismatch: []
  };

  for (const file of sourceFiles) {
    const destPath = path.join(repoDir, destDir, file.path);

    // Check if file exists
    if (!await fs.pathExists(destPath)) {
      results.missing.push(file.path);
      continue;
    }

    results.found++;

    // Verify content matches
    const destContent = await fs.readFile(destPath, 'utf8');
    if (destContent !== file.content) {
      results.contentMismatch.push({
        path: file.path,
        expected: file.content.substring(0, 100),
        actual: destContent.substring(0, 100)
      });
    }
  }

  return results;
}

describe('Property Test: File Consolidation Completeness', () => {
  it('should consolidate all files from source to destination with equivalent content (100 iterations)', async () => {
    const iterations = 100;
    let passedIterations = 0;

    for (let i = 0; i < iterations; i++) {
      const repoDir = await createTestRepo();

      try {
        // Generate random file structure (1-10 files per iteration)
        const fileCount = Math.floor(Math.random() * 10) + 1;
        const files = generateRandomFileStructure(fileCount);

        // Choose random source directory
        const sourceDirs = ['plan', 'plans'];
        const sourceDir = sourceDirs[Math.floor(Math.random() * sourceDirs.length)];
        const destDir = 'docs/plans';

        // Create files in source directory
        await createFilesInRepo(repoDir, sourceDir, files);

        // Execute consolidation
        const movedFiles = await executeConsolidation(repoDir, sourceDir, destDir);

        // Verify all files exist in destination with correct content
        const verification = await verifyConsolidation(repoDir, files, destDir);

        // Assert completeness
        assert.strictEqual(
          verification.missing.length,
          0,
          `Iteration ${i + 1}: Missing files in destination: ${verification.missing.join(', ')}`
        );

        assert.strictEqual(
          verification.contentMismatch.length,
          0,
          `Iteration ${i + 1}: Content mismatch in files: ${JSON.stringify(verification.contentMismatch)}`
        );

        assert.strictEqual(
          verification.found,
          verification.total,
          `Iteration ${i + 1}: Expected ${verification.total} files, found ${verification.found}`
        );

        passedIterations++;
      } finally {
        // Clean up test repository
        await fs.remove(repoDir);
      }
    }

    // Verify all iterations passed
    assert.strictEqual(
      passedIterations,
      iterations,
      `Expected all ${iterations} iterations to pass, but only ${passedIterations} passed`
    );
  });

  it('should handle empty source directories', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create empty source directory
      await fs.ensureDir(path.join(repoDir, sourceDir));
      execSync(`git add "${sourceDir}"`, { cwd: repoDir, stdio: 'pipe' });
      execSync(`git commit -m "Add empty ${sourceDir}" --allow-empty`, {
        cwd: repoDir,
        stdio: 'pipe'
      });

      // Execute consolidation
      const movedFiles = await executeConsolidation(repoDir, sourceDir, destDir);

      // Verify no files were moved
      assert.strictEqual(movedFiles.length, 0, 'Expected no files to be moved from empty directory');
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should preserve directory structure during consolidation', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create files with nested directory structure
      const files = [
        { path: 'root.md', content: 'root content' },
        { path: 'subdir1/file1.md', content: 'file1 content' },
        { path: 'subdir1/subdir2/file2.md', content: 'file2 content' },
        { path: 'subdir3/file3.md', content: 'file3 content' }
      ];

      await createFilesInRepo(repoDir, sourceDir, files);

      // Execute consolidation
      await executeConsolidation(repoDir, sourceDir, destDir);

      // Verify directory structure is preserved
      for (const file of files) {
        const destPath = path.join(repoDir, destDir, file.path);
        assert.ok(
          await fs.pathExists(destPath),
          `Expected file to exist at ${destPath}`
        );

        const content = await fs.readFile(destPath, 'utf8');
        assert.strictEqual(
          content,
          file.content,
          `Content mismatch for ${file.path}`
        );
      }
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle files with special characters in names', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create files with special characters (avoiding characters that are invalid in filenames)
      const files = [
        { path: 'file-with-dashes.md', content: 'content1' },
        { path: 'file_with_underscores.md', content: 'content2' },
        { path: 'file.with.dots.md', content: 'content3' },
        { path: 'file with spaces.md', content: 'content4' }
      ];

      await createFilesInRepo(repoDir, sourceDir, files);

      // Execute consolidation
      await executeConsolidation(repoDir, sourceDir, destDir);

      // Verify all files exist with correct content
      const verification = await verifyConsolidation(repoDir, files, destDir);

      assert.strictEqual(verification.missing.length, 0, 'No files should be missing');
      assert.strictEqual(verification.contentMismatch.length, 0, 'No content mismatches');
      assert.strictEqual(verification.found, files.length, 'All files should be found');
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle large files during consolidation', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourceDir = 'plan';
      const destDir = 'docs/plans';

      // Create large files (1MB each)
      const largeContent = crypto.randomBytes(1024 * 1024).toString('hex');
      const files = [
        { path: 'large1.md', content: largeContent },
        { path: 'large2.md', content: largeContent }
      ];

      await createFilesInRepo(repoDir, sourceDir, files);

      // Execute consolidation
      await executeConsolidation(repoDir, sourceDir, destDir);

      // Verify files exist with correct content
      const verification = await verifyConsolidation(repoDir, files, destDir);

      assert.strictEqual(verification.missing.length, 0, 'No files should be missing');
      assert.strictEqual(verification.contentMismatch.length, 0, 'No content mismatches');
      assert.strictEqual(verification.found, files.length, 'All files should be found');
    } finally {
      await fs.remove(repoDir);
    }
  });
});

/**
 * Property-Based Test: Git History Preservation
 *
 * **Validates: Requirements 1.4, 14.3**
 *
 * Property 2: Git History Preservation
 * For any file moved during consolidation, the git history for that file
 * should be accessible at the new location using `git log`.
 *
 * This test generates random files with git history (multiple commits),
 * executes git mv operations, and verifies git log --follow shows complete
 * history at the new location.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import { execSync } from 'child_process';
import fs from 'fs-extra';
import path from 'path';
import os from 'os';
import crypto from 'crypto';
import { executeGitMv, verifyHistoryPreservation } from '../../lib/git-operations.js';

/**
 * Creates a temporary git repository for testing
 */
async function createTestRepo() {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'git-history-test-'));

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
 * Creates a file with multiple commits to establish git history
 * @param {string} repoDir - Repository directory
 * @param {string} filePath - File path relative to repo root
 * @param {number} commitCount - Number of commits to create
 * @returns {Promise<Array<string>>} Array of commit messages
 */
async function createFileWithHistory(repoDir, filePath, commitCount) {
  const absolutePath = path.join(repoDir, filePath);
  const commitMessages = [];

  // Ensure directory exists
  await fs.ensureDir(path.dirname(absolutePath));

  // Create initial file and commit
  const initialContent = generateRandomContent();
  await fs.writeFile(absolutePath, initialContent, 'utf8');
  execSync(`git add "${filePath}"`, { cwd: repoDir, stdio: 'pipe' });
  
  const initialMessage = `Initial commit for ${filePath}`;
  execSync(`git commit -m "${initialMessage}"`, { cwd: repoDir, stdio: 'pipe' });
  commitMessages.push(initialMessage);

  // Create additional commits by modifying the file
  for (let i = 1; i < commitCount; i++) {
    const newContent = generateRandomContent();
    await fs.appendFile(absolutePath, `\n${newContent}`, 'utf8');
    execSync(`git add "${filePath}"`, { cwd: repoDir, stdio: 'pipe' });
    
    const message = `Update ${i} for ${filePath}`;
    execSync(`git commit -m "${message}"`, { cwd: repoDir, stdio: 'pipe' });
    commitMessages.push(message);
  }

  return commitMessages;
}

/**
 * Gets the git log for a file using --follow to track renames
 * @param {string} repoDir - Repository directory
 * @param {string} filePath - File path relative to repo root
 * @returns {Array<string>} Array of commit messages
 */
function getGitLog(repoDir, filePath) {
  try {
    const output = execSync(
      `git log --follow --oneline -- "${filePath}"`,
      {
        cwd: repoDir,
        encoding: 'utf8',
        stdio: 'pipe'
      }
    );

    return output.trim().split('\n').filter((line) => line.length > 0);
  } catch (error) {
    return [];
  }
}

/**
 * Generates a random file path with directory structure
 */
function generateRandomFilePath(maxDepth = 3) {
  const pathParts = [];
  const depth = Math.floor(Math.random() * (maxDepth + 1));

  for (let d = 0; d < depth; d++) {
    pathParts.push(`dir${Math.floor(Math.random() * 5)}`);
  }

  const extensions = ['.md', '.txt', '.json', '.yaml'];
  const ext = extensions[Math.floor(Math.random() * extensions.length)];
  const filename = `file${Math.floor(Math.random() * 1000)}${ext}`;
  pathParts.push(filename);

  return pathParts.join('/');
}

describe('Property Test: Git History Preservation', () => {
  it('should preserve git history after moving files (100 iterations)', async () => {
    const iterations = 100;
    let passedIterations = 0;

    for (let i = 0; i < iterations; i++) {
      const repoDir = await createTestRepo();

      try {
        // Generate random file path and commit count (2-10 commits)
        const commitCount = Math.floor(Math.random() * 9) + 2;
        const sourceDir = Math.random() > 0.5 ? 'plan' : 'plans';
        const sourceFile = generateRandomFilePath();
        const sourcePath = path.join(sourceDir, sourceFile);
        
        // Create destination path
        const destPath = path.join('docs/plans', sourceFile);

        // Create file with git history
        const commitMessages = await createFileWithHistory(repoDir, sourcePath, commitCount);

        // Get git log before move
        const logBefore = getGitLog(repoDir, sourcePath);
        assert.strictEqual(
          logBefore.length,
          commitCount,
          `Iteration ${i + 1}: Expected ${commitCount} commits before move, got ${logBefore.length}`
        );

        // Execute git mv
        await executeGitMv(sourcePath, destPath, { repoRoot: repoDir });

        // Commit the move
        execSync(`git commit -m "Move ${sourcePath} to ${destPath}"`, {
          cwd: repoDir,
          stdio: 'pipe'
        });

        // Get git log after move using --follow
        const logAfter = getGitLog(repoDir, destPath);

        // Verify history is preserved (should have original commits + move commit)
        assert.ok(
          logAfter.length >= commitCount,
          `Iteration ${i + 1}: Expected at least ${commitCount} commits after move, got ${logAfter.length}`
        );

        // Verify using verifyHistoryPreservation function
        const verification = await verifyHistoryPreservation(destPath, {
          repoRoot: repoDir,
          minCommits: commitCount
        });

        assert.ok(
          verification.preserved,
          `Iteration ${i + 1}: History not preserved: ${verification.message}`
        );

        assert.strictEqual(
          verification.commitCount,
          logAfter.length,
          `Iteration ${i + 1}: Commit count mismatch`
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

  it('should preserve history for files with single commit', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourcePath = 'plan/single-commit.md';
      const destPath = 'docs/plans/single-commit.md';

      // Create file with single commit
      await createFileWithHistory(repoDir, sourcePath, 1);

      // Execute git mv
      await executeGitMv(sourcePath, destPath, { repoRoot: repoDir });
      execSync(`git commit -m "Move ${sourcePath} to ${destPath}"`, {
        cwd: repoDir,
        stdio: 'pipe'
      });

      // Verify history is preserved
      const verification = await verifyHistoryPreservation(destPath, {
        repoRoot: repoDir,
        minCommits: 1
      });

      assert.ok(verification.preserved, 'History should be preserved for single commit file');
      assert.ok(verification.commitCount >= 1, 'Should have at least 1 commit');
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should preserve history for files with many commits', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourcePath = 'plan/many-commits.md';
      const destPath = 'docs/plans/many-commits.md';
      const commitCount = 20;

      // Create file with many commits
      await createFileWithHistory(repoDir, sourcePath, commitCount);

      // Execute git mv
      await executeGitMv(sourcePath, destPath, { repoRoot: repoDir });
      execSync(`git commit -m "Move ${sourcePath} to ${destPath}"`, {
        cwd: repoDir,
        stdio: 'pipe'
      });

      // Verify history is preserved
      const verification = await verifyHistoryPreservation(destPath, {
        repoRoot: repoDir,
        minCommits: commitCount
      });

      assert.ok(verification.preserved, 'History should be preserved for file with many commits');
      assert.ok(
        verification.commitCount >= commitCount,
        `Should have at least ${commitCount} commits, got ${verification.commitCount}`
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should preserve history across nested directory moves', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourcePath = 'plan/deep/nested/structure/file.md';
      const destPath = 'docs/plans/different/nested/path/file.md';
      const commitCount = 5;

      // Create file with history in nested structure
      await createFileWithHistory(repoDir, sourcePath, commitCount);

      // Execute git mv
      await executeGitMv(sourcePath, destPath, { repoRoot: repoDir });
      execSync(`git commit -m "Move ${sourcePath} to ${destPath}"`, {
        cwd: repoDir,
        stdio: 'pipe'
      });

      // Verify history is preserved
      const verification = await verifyHistoryPreservation(destPath, {
        repoRoot: repoDir,
        minCommits: commitCount
      });

      assert.ok(verification.preserved, 'History should be preserved across nested directory moves');
      assert.ok(
        verification.commitCount >= commitCount,
        `Should have at least ${commitCount} commits`
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should preserve history for files with special characters', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourcePath = 'plan/file-with-dashes_and_underscores.md';
      const destPath = 'docs/plans/file-with-dashes_and_underscores.md';
      const commitCount = 3;

      // Create file with history
      await createFileWithHistory(repoDir, sourcePath, commitCount);

      // Execute git mv
      await executeGitMv(sourcePath, destPath, { repoRoot: repoDir });
      execSync(`git commit -m "Move file with special characters"`, {
        cwd: repoDir,
        stdio: 'pipe'
      });

      // Verify history is preserved
      const verification = await verifyHistoryPreservation(destPath, {
        repoRoot: repoDir,
        minCommits: commitCount
      });

      assert.ok(verification.preserved, 'History should be preserved for files with special characters');
      assert.ok(
        verification.commitCount >= commitCount,
        `Should have at least ${commitCount} commits`
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should detect when history is not preserved (negative test)', async () => {
    const repoDir = await createTestRepo();

    try {
      const sourcePath = 'plan/file.md';
      const destPath = 'docs/plans/file.md';
      const commitCount = 3;

      // Create file with history
      await createFileWithHistory(repoDir, sourcePath, commitCount);

      // Simulate incorrect move by creating a new file with different content
      // This ensures git won't detect it as a rename
      const absoluteDest = path.join(repoDir, destPath);
      await fs.ensureDir(path.dirname(absoluteDest));
      await fs.writeFile(absoluteDest, 'completely new content', 'utf8');

      // Remove source file
      execSync(`git rm "${sourcePath}"`, { cwd: repoDir, stdio: 'pipe' });

      // Stage and commit the new file
      execSync(`git add "${destPath}"`, { cwd: repoDir, stdio: 'pipe' });
      execSync(`git commit -m "Delete old file and create new file (not git mv)"`, {
        cwd: repoDir,
        stdio: 'pipe'
      });

      // Verify history is NOT preserved (should only have 1 commit - the new file)
      const verification = await verifyHistoryPreservation(destPath, {
        repoRoot: repoDir,
        minCommits: commitCount
      });

      assert.ok(
        !verification.preserved,
        'History should NOT be preserved when creating a new file instead of using git mv'
      );
      assert.strictEqual(
        verification.commitCount,
        1,
        `Should have exactly 1 commit when history is not preserved, got ${verification.commitCount}`
      );
    } finally {
      await fs.remove(repoDir);
    }
  });

  it('should handle multiple sequential moves preserving full history', async () => {
    const repoDir = await createTestRepo();

    try {
      const path1 = 'plan/file.md';
      const path2 = 'plans/file.md';
      const path3 = 'docs/plans/file.md';
      const commitCount = 4;

      // Create file with history
      await createFileWithHistory(repoDir, path1, commitCount);

      // First move
      await executeGitMv(path1, path2, { repoRoot: repoDir });
      execSync(`git commit -m "Move to plans/"`, { cwd: repoDir, stdio: 'pipe' });

      // Second move
      await executeGitMv(path2, path3, { repoRoot: repoDir });
      execSync(`git commit -m "Move to docs/plans/"`, { cwd: repoDir, stdio: 'pipe' });

      // Verify full history is preserved through multiple moves
      const verification = await verifyHistoryPreservation(path3, {
        repoRoot: repoDir,
        minCommits: commitCount
      });

      assert.ok(
        verification.preserved,
        'History should be preserved through multiple sequential moves'
      );
      assert.ok(
        verification.commitCount >= commitCount,
        `Should have at least ${commitCount} commits after multiple moves`
      );
    } finally {
      await fs.remove(repoDir);
    }
  });
});

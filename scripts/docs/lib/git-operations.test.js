/**
 * Unit Tests for Git Operations
 *
 * Tests git mv operations, batch processing, rollback, and history verification.
 */

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { execSync } from 'child_process';
import fs from 'fs-extra';
import path from 'path';
import os from 'os';
import {
  isGitRepository,
  isFileTracked,
  executeGitMv,
  batchGitMv,
  rollbackGitMv,
  verifyHistoryPreservation,
  GitOperationError
} from './git-operations.js';

/**
 * Creates a temporary git repository for testing
 */
async function createTestRepo() {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'git-ops-test-'));

  // Initialize git repo
  execSync('git init', { cwd: tmpDir, stdio: 'pipe' });
  execSync('git config user.email "test@example.com"', { cwd: tmpDir, stdio: 'pipe' });
  execSync('git config user.name "Test User"', { cwd: tmpDir, stdio: 'pipe' });

  return tmpDir;
}

/**
 * Creates a test file with git history
 */
async function createTrackedFile(repoDir, filePath, content = 'test content') {
  const fullPath = path.join(repoDir, filePath);
  await fs.ensureDir(path.dirname(fullPath));
  await fs.writeFile(fullPath, content);

  execSync(`git add "${filePath}"`, { cwd: repoDir, stdio: 'pipe' });
  execSync(`git commit -m "Add ${filePath}"`, { cwd: repoDir, stdio: 'pipe' });

  return fullPath;
}

describe('Git Operations', () => {
  describe('isGitRepository', () => {
    it('should return true for a git repository', async () => {
      const tmpDir = await createTestRepo();
      try {
        assert.strictEqual(isGitRepository(tmpDir), true);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should return false for a non-git directory', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'non-git-'));
      try {
        assert.strictEqual(isGitRepository(tmpDir), false);
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('isFileTracked', () => {
    it('should return true for tracked files', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'test.txt');
        assert.strictEqual(isFileTracked('test.txt', tmpDir), true);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should return false for untracked files', async () => {
      const tmpDir = await createTestRepo();
      try {
        await fs.writeFile(path.join(tmpDir, 'untracked.txt'), 'content');
        assert.strictEqual(isFileTracked('untracked.txt', tmpDir), false);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should return false for non-existent files', async () => {
      const tmpDir = await createTestRepo();
      try {
        assert.strictEqual(isFileTracked('nonexistent.txt', tmpDir), false);
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('executeGitMv', () => {
    it('should successfully move a tracked file', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'source.txt', 'test content');

        const result = await executeGitMv('source.txt', 'dest.txt', {
          repoRoot: tmpDir
        });

        assert.strictEqual(result.success, true);
        assert.strictEqual(result.sourcePath, 'source.txt');
        assert.strictEqual(result.destPath, 'dest.txt');
        assert.ok(await fs.pathExists(path.join(tmpDir, 'dest.txt')));
        assert.ok(!await fs.pathExists(path.join(tmpDir, 'source.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should create destination directory if it does not exist', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'source.txt');

        const result = await executeGitMv('source.txt', 'subdir/dest.txt', {
          repoRoot: tmpDir
        });

        assert.strictEqual(result.success, true);
        assert.ok(await fs.pathExists(path.join(tmpDir, 'subdir/dest.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle dry run mode', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'source.txt');

        const result = await executeGitMv('source.txt', 'dest.txt', {
          repoRoot: tmpDir,
          dryRun: true
        });

        assert.strictEqual(result.success, true);
        assert.strictEqual(result.dryRun, true);
        // File should not actually move in dry run
        assert.ok(await fs.pathExists(path.join(tmpDir, 'source.txt')));
        assert.ok(!await fs.pathExists(path.join(tmpDir, 'dest.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for non-existent source file', async () => {
      const tmpDir = await createTestRepo();
      try {
        await assert.rejects(
          async () => {
            await executeGitMv('nonexistent.txt', 'dest.txt', {
              repoRoot: tmpDir
            });
          },
          {
            name: 'GitOperationError',
            message: /does not exist/
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for untracked source file', async () => {
      const tmpDir = await createTestRepo();
      try {
        await fs.writeFile(path.join(tmpDir, 'untracked.txt'), 'content');

        await assert.rejects(
          async () => {
            await executeGitMv('untracked.txt', 'dest.txt', {
              repoRoot: tmpDir
            });
          },
          {
            name: 'GitOperationError',
            message: /not tracked/
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error if not in a git repository', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'non-git-'));
      try {
        await assert.rejects(
          async () => {
            await executeGitMv('source.txt', 'dest.txt', {
              repoRoot: tmpDir
            });
          },
          {
            name: 'GitOperationError',
            message: /Not a git repository/
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for missing source or destination', async () => {
      const tmpDir = await createTestRepo();
      try {
        await assert.rejects(
          async () => {
            await executeGitMv('', 'dest.txt', { repoRoot: tmpDir });
          },
          {
            name: 'GitOperationError',
            message: /required/
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('batchGitMv', () => {
    it('should successfully move multiple files', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');
        await createTrackedFile(tmpDir, 'file2.txt');
        await createTrackedFile(tmpDir, 'file3.txt');

        const fileList = [
          { source: 'file1.txt', destination: 'moved1.txt' },
          { source: 'file2.txt', destination: 'moved2.txt' },
          { source: 'file3.txt', destination: 'moved3.txt' }
        ];

        const result = await batchGitMv(fileList, {
          repoRoot: tmpDir
        });

        assert.strictEqual(result.success, true);
        assert.strictEqual(result.summary.total, 3);
        assert.strictEqual(result.summary.success, 3);
        assert.strictEqual(result.summary.failed, 0);
        assert.strictEqual(result.results.length, 3);
        assert.strictEqual(result.errors.length, 0);

        // Verify files moved
        assert.ok(await fs.pathExists(path.join(tmpDir, 'moved1.txt')));
        assert.ok(await fs.pathExists(path.join(tmpDir, 'moved2.txt')));
        assert.ok(await fs.pathExists(path.join(tmpDir, 'moved3.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should call progress callback for each file', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');
        await createTrackedFile(tmpDir, 'file2.txt');

        const fileList = [
          { source: 'file1.txt', destination: 'moved1.txt' },
          { source: 'file2.txt', destination: 'moved2.txt' }
        ];

        const progressCalls = [];
        const result = await batchGitMv(fileList, {
          repoRoot: tmpDir,
          onProgress: (current, total, result) => {
            progressCalls.push({ current, total, result });
          }
        });

        assert.strictEqual(result.success, true);
        assert.strictEqual(progressCalls.length, 2);
        assert.strictEqual(progressCalls[0].current, 1);
        assert.strictEqual(progressCalls[0].total, 2);
        assert.strictEqual(progressCalls[1].current, 2);
        assert.strictEqual(progressCalls[1].total, 2);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle dry run mode for batch operations', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');
        await createTrackedFile(tmpDir, 'file2.txt');

        const fileList = [
          { source: 'file1.txt', destination: 'moved1.txt' },
          { source: 'file2.txt', destination: 'moved2.txt' }
        ];

        const result = await batchGitMv(fileList, {
          repoRoot: tmpDir,
          dryRun: true
        });

        assert.strictEqual(result.success, true);
        assert.strictEqual(result.summary.success, 2);

        // Files should not actually move
        assert.ok(await fs.pathExists(path.join(tmpDir, 'file1.txt')));
        assert.ok(await fs.pathExists(path.join(tmpDir, 'file2.txt')));
        assert.ok(!await fs.pathExists(path.join(tmpDir, 'moved1.txt')));
        assert.ok(!await fs.pathExists(path.join(tmpDir, 'moved2.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should rollback on failure when continueOnError is false', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');
        await createTrackedFile(tmpDir, 'file2.txt');

        const fileList = [
          { source: 'file1.txt', destination: 'moved1.txt' },
          { source: 'nonexistent.txt', destination: 'moved2.txt' }, // This will fail
          { source: 'file2.txt', destination: 'moved3.txt' }
        ];

        await assert.rejects(
          async () => {
            await batchGitMv(fileList, {
              repoRoot: tmpDir,
              continueOnError: false
            });
          },
          {
            name: 'GitOperationError',
            message: /Batch operation failed/
          }
        );

        // First file should be rolled back
        assert.ok(await fs.pathExists(path.join(tmpDir, 'file1.txt')));
        assert.ok(!await fs.pathExists(path.join(tmpDir, 'moved1.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should continue on failure when continueOnError is true', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');
        await createTrackedFile(tmpDir, 'file2.txt');

        const fileList = [
          { source: 'file1.txt', destination: 'moved1.txt' },
          { source: 'nonexistent.txt', destination: 'moved2.txt' }, // This will fail
          { source: 'file2.txt', destination: 'moved3.txt' }
        ];

        const result = await batchGitMv(fileList, {
          repoRoot: tmpDir,
          continueOnError: true
        });

        assert.strictEqual(result.success, false);
        assert.strictEqual(result.summary.success, 2);
        assert.strictEqual(result.summary.skipped, 0);
        assert.strictEqual(result.summary.failed, 1);
        assert.strictEqual(result.errors.length, 1);

        // Successful moves should remain
        assert.ok(await fs.pathExists(path.join(tmpDir, 'moved1.txt')));
        assert.ok(await fs.pathExists(path.join(tmpDir, 'moved3.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle invalid file entries', async () => {
      const tmpDir = await createTestRepo();
      try {
        const fileList = [
          { source: 'file1.txt' }, // Missing destination
          { destination: 'moved2.txt' }, // Missing source
          null // Invalid entry
        ];

        const result = await batchGitMv(fileList, {
          repoRoot: tmpDir,
          continueOnError: true
        });

        assert.strictEqual(result.success, false);
        assert.strictEqual(result.summary.failed, 3);
        assert.strictEqual(result.errors.length, 3);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for empty file list', async () => {
      const tmpDir = await createTestRepo();
      try {
        await assert.rejects(
          async () => {
            await batchGitMv([], { repoRoot: tmpDir });
          },
          {
            name: 'GitOperationError',
            message: /non-empty array/
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('rollbackGitMv', () => {
    it('should rollback successful moves', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');
        await createTrackedFile(tmpDir, 'file2.txt');

        // Perform moves
        const result1 = await executeGitMv('file1.txt', 'moved1.txt', {
          repoRoot: tmpDir
        });
        const result2 = await executeGitMv('file2.txt', 'moved2.txt', {
          repoRoot: tmpDir
        });

        // Rollback
        const rollbackResult = await rollbackGitMv([result1, result2], {
          repoRoot: tmpDir
        });

        assert.strictEqual(rollbackResult.success, true);
        assert.strictEqual(rollbackResult.rolledBack, 2);
        assert.strictEqual(rollbackResult.failed, 0);

        // Files should be back at original locations
        assert.ok(await fs.pathExists(path.join(tmpDir, 'file1.txt')));
        assert.ok(await fs.pathExists(path.join(tmpDir, 'file2.txt')));
        assert.ok(!await fs.pathExists(path.join(tmpDir, 'moved1.txt')));
        assert.ok(!await fs.pathExists(path.join(tmpDir, 'moved2.txt')));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should skip dry run results', async () => {
      const tmpDir = await createTestRepo();
      try {
        const results = [
          { success: true, dryRun: true, sourcePath: 'file1.txt', destPath: 'moved1.txt' }
        ];

        const rollbackResult = await rollbackGitMv(results, {
          repoRoot: tmpDir
        });

        assert.strictEqual(rollbackResult.success, true);
        assert.strictEqual(rollbackResult.rolledBack, 0);
        assert.ok(rollbackResult.message.includes('No operations'));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should skip failed results', async () => {
      const tmpDir = await createTestRepo();
      try {
        const results = [
          { success: false, sourcePath: 'file1.txt', destPath: 'moved1.txt' }
        ];

        const rollbackResult = await rollbackGitMv(results, {
          repoRoot: tmpDir
        });

        assert.strictEqual(rollbackResult.success, true);
        assert.strictEqual(rollbackResult.rolledBack, 0);
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('verifyHistoryPreservation', () => {
    it('should verify history is preserved after move', async () => {
      const tmpDir = await createTestRepo();
      try {
        // Create file with multiple commits
        await createTrackedFile(tmpDir, 'source.txt', 'initial content');
        await fs.writeFile(path.join(tmpDir, 'source.txt'), 'updated content');
        execSync('git add source.txt', { cwd: tmpDir, stdio: 'pipe' });
        execSync('git commit -m "Update source.txt"', { cwd: tmpDir, stdio: 'pipe' });

        // Move file
        await executeGitMv('source.txt', 'dest.txt', {
          repoRoot: tmpDir
        });

        // Commit the move (required for git log --follow to work)
        execSync('git commit -m "Move source.txt to dest.txt"', { cwd: tmpDir, stdio: 'pipe' });

        // Verify history
        const verification = await verifyHistoryPreservation('dest.txt', {
          repoRoot: tmpDir,
          minCommits: 2
        });

        assert.strictEqual(verification.preserved, true);
        assert.strictEqual(verification.commitCount, 3); // 2 original + 1 move
        assert.ok(Array.isArray(verification.history));
        assert.strictEqual(verification.history.length, 3);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should return false for non-existent file', async () => {
      const tmpDir = await createTestRepo();
      try {
        const verification = await verifyHistoryPreservation('nonexistent.txt', {
          repoRoot: tmpDir
        });

        assert.strictEqual(verification.preserved, false);
        assert.strictEqual(verification.commitCount, 0);
        assert.ok(verification.message.includes('does not exist'));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should return false if insufficient commits', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file.txt');

        const verification = await verifyHistoryPreservation('file.txt', {
          repoRoot: tmpDir,
          minCommits: 5
        });

        assert.strictEqual(verification.preserved, false);
        assert.strictEqual(verification.commitCount, 1);
        assert.ok(verification.message.includes('Insufficient history'));
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });
});

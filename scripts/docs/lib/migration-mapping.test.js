/**
 * Unit Tests for Migration Mapping Generator
 *
 * Tests migration mapping generation, file metadata capture, and mapping
 * file I/O operations.
 */

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { execSync } from 'child_process';
import fs from 'fs-extra';
import path from 'path';
import os from 'os';
import {
  generateMappingEntry,
  generateMigrationMapping,
  writeMigrationMapping,
  generateAndWriteMapping,
  readMigrationMapping,
  lookupNewPath,
  lookupOldPath
} from './migration-mapping.js';

/**
 * Creates a temporary git repository for testing
 */
async function createTestRepo() {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'migration-mapping-test-'));

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

describe('Migration Mapping Generator', () => {
  describe('generateMappingEntry', () => {
    it('should generate mapping entry with file metadata', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'source.txt', 'test content');

        const entry = await generateMappingEntry(
          'source.txt',
          'dest.txt',
          tmpDir
        );

        assert.strictEqual(entry.oldPath, 'source.txt');
        assert.strictEqual(entry.newPath, 'dest.txt');
        assert.strictEqual(typeof entry.size, 'number');
        assert.ok(entry.size > 0);
        assert.strictEqual(typeof entry.lastModified, 'string');
        assert.ok(entry.lastModified.match(/^\d{4}-\d{2}-\d{2}T/)); // ISO date format
        assert.strictEqual(typeof entry.gitCommit, 'string');
        assert.strictEqual(entry.gitCommit.length, 40); // Git SHA-1 hash
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle non-existent files gracefully', async () => {
      const tmpDir = await createTestRepo();
      try {
        const entry = await generateMappingEntry(
          'nonexistent.txt',
          'dest.txt',
          tmpDir
        );

        assert.strictEqual(entry.oldPath, 'nonexistent.txt');
        assert.strictEqual(entry.newPath, 'dest.txt');
        assert.strictEqual(entry.size, null);
        assert.strictEqual(entry.lastModified, null);
        assert.strictEqual(entry.gitCommit, null);
        assert.ok(entry.error);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle files without git history', async () => {
      const tmpDir = await createTestRepo();
      try {
        // Create untracked file
        await fs.writeFile(path.join(tmpDir, 'untracked.txt'), 'content');

        const entry = await generateMappingEntry(
          'untracked.txt',
          'dest.txt',
          tmpDir
        );

        assert.strictEqual(entry.oldPath, 'untracked.txt');
        assert.strictEqual(entry.newPath, 'dest.txt');
        assert.strictEqual(typeof entry.size, 'number');
        assert.strictEqual(typeof entry.lastModified, 'string');
        assert.strictEqual(entry.gitCommit, null); // No git history
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should capture correct file size', async () => {
      const tmpDir = await createTestRepo();
      try {
        const content = 'a'.repeat(1000); // 1000 bytes
        await createTrackedFile(tmpDir, 'large.txt', content);

        const entry = await generateMappingEntry(
          'large.txt',
          'dest.txt',
          tmpDir
        );

        assert.strictEqual(entry.size, 1000);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle files in subdirectories', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'subdir/file.txt');

        const entry = await generateMappingEntry(
          'subdir/file.txt',
          'newdir/file.txt',
          tmpDir
        );

        assert.strictEqual(entry.oldPath, 'subdir/file.txt');
        assert.strictEqual(entry.newPath, 'newdir/file.txt');
        assert.ok(entry.size > 0);
        assert.ok(entry.gitCommit);
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('generateMigrationMapping', () => {
    it('should generate mapping for multiple files', async () => {
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

        const mapping = await generateMigrationMapping(fileList, tmpDir);

        assert.strictEqual(mapping.version, '1.0.0');
        assert.ok(mapping.generatedAt);
        assert.strictEqual(mapping.repoRoot, tmpDir);
        assert.strictEqual(mapping.totalFiles, 3);
        assert.strictEqual(mapping.successfulMappings, 3);
        assert.strictEqual(mapping.failedMappings, 0);
        assert.strictEqual(mapping.mappings.length, 3);
        assert.strictEqual(mapping.errors, undefined);

        // Verify each mapping
        assert.strictEqual(mapping.mappings[0].oldPath, 'file1.txt');
        assert.strictEqual(mapping.mappings[0].newPath, 'moved1.txt');
        assert.strictEqual(mapping.mappings[1].oldPath, 'file2.txt');
        assert.strictEqual(mapping.mappings[1].newPath, 'moved2.txt');
        assert.strictEqual(mapping.mappings[2].oldPath, 'file3.txt');
        assert.strictEqual(mapping.mappings[2].newPath, 'moved3.txt');
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle empty file list', async () => {
      const tmpDir = await createTestRepo();
      try {
        const mapping = await generateMigrationMapping([], tmpDir);

        assert.strictEqual(mapping.totalFiles, 0);
        assert.strictEqual(mapping.successfulMappings, 0);
        assert.strictEqual(mapping.failedMappings, 0);
        assert.strictEqual(mapping.mappings.length, 0);
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
          null, // Invalid entry
          'invalid' // Invalid entry
        ];

        const mapping = await generateMigrationMapping(fileList, tmpDir);

        assert.strictEqual(mapping.totalFiles, 4);
        assert.strictEqual(mapping.successfulMappings, 0);
        assert.strictEqual(mapping.failedMappings, 4);
        assert.strictEqual(mapping.mappings.length, 0);
        assert.ok(Array.isArray(mapping.errors));
        assert.strictEqual(mapping.errors.length, 4);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should handle mix of valid and invalid entries', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');

        const fileList = [
          { source: 'file1.txt', destination: 'moved1.txt' }, // Valid
          { source: 'nonexistent.txt', destination: 'moved2.txt' }, // Valid but file doesn't exist
          { source: 'file3.txt' }, // Invalid - missing destination
          null // Invalid entry
        ];

        const mapping = await generateMigrationMapping(fileList, tmpDir);

        assert.strictEqual(mapping.totalFiles, 4);
        assert.strictEqual(mapping.successfulMappings, 2);
        assert.strictEqual(mapping.failedMappings, 2);
        assert.strictEqual(mapping.mappings.length, 2);
        assert.strictEqual(mapping.errors.length, 2);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for non-array input', async () => {
      const tmpDir = await createTestRepo();
      try {
        await assert.rejects(
          async () => {
            await generateMigrationMapping('not an array', tmpDir);
          },
          {
            name: 'TypeError',
            message: /must be an array/
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should include generatedAt timestamp', async () => {
      const tmpDir = await createTestRepo();
      try {
        const before = new Date();
        const mapping = await generateMigrationMapping([], tmpDir);
        const after = new Date();

        const generatedAt = new Date(mapping.generatedAt);
        assert.ok(generatedAt >= before);
        assert.ok(generatedAt <= after);
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('writeMigrationMapping', () => {
    it('should write mapping to JSON file', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'mapping-write-test-'));
      try {
        const mapping = {
          version: '1.0.0',
          generatedAt: new Date().toISOString(),
          totalFiles: 1,
          mappings: [
            {
              oldPath: 'old.txt',
              newPath: 'new.txt',
              size: 100,
              lastModified: new Date().toISOString(),
              gitCommit: 'abc123'
            }
          ]
        };

        const outputPath = path.join(tmpDir, 'mapping.json');
        await writeMigrationMapping(mapping, outputPath);

        // Verify file exists
        assert.ok(await fs.pathExists(outputPath));

        // Verify content
        const content = await fs.readFile(outputPath, 'utf8');
        const parsed = JSON.parse(content);
        assert.deepStrictEqual(parsed, mapping);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should create output directory if it does not exist', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'mapping-write-test-'));
      try {
        const mapping = {
          version: '1.0.0',
          mappings: []
        };

        const outputPath = path.join(tmpDir, 'subdir', 'nested', 'mapping.json');
        await writeMigrationMapping(mapping, outputPath);

        assert.ok(await fs.pathExists(outputPath));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should format JSON with indentation', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'mapping-write-test-'));
      try {
        const mapping = {
          version: '1.0.0',
          mappings: [{ oldPath: 'a', newPath: 'b' }]
        };

        const outputPath = path.join(tmpDir, 'mapping.json');
        await writeMigrationMapping(mapping, outputPath);

        const content = await fs.readFile(outputPath, 'utf8');
        // Check for indentation (2 spaces)
        assert.ok(content.includes('  "version"'));
        assert.ok(content.includes('  "mappings"'));
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for invalid mapping', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'mapping-write-test-'));
      try {
        await assert.rejects(
          async () => {
            await writeMigrationMapping(null, path.join(tmpDir, 'mapping.json'));
          },
          {
            name: 'TypeError',
            message: /must be an object/
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for invalid output path', async () => {
      await assert.rejects(
        async () => {
          await writeMigrationMapping({ version: '1.0.0' }, null);
        },
        {
          name: 'TypeError',
          message: /must be a string/
        }
      );
    });
  });

  describe('generateAndWriteMapping', () => {
    it('should generate and write mapping in one operation', async () => {
      const tmpDir = await createTestRepo();
      try {
        await createTrackedFile(tmpDir, 'file1.txt');
        await createTrackedFile(tmpDir, 'file2.txt');

        const fileList = [
          { source: 'file1.txt', destination: 'moved1.txt' },
          { source: 'file2.txt', destination: 'moved2.txt' }
        ];

        const outputPath = path.join(tmpDir, 'mapping.json');
        const mapping = await generateAndWriteMapping(fileList, outputPath, {
          repoRoot: tmpDir
        });

        // Verify return value
        assert.strictEqual(mapping.totalFiles, 2);
        assert.strictEqual(mapping.successfulMappings, 2);

        // Verify file was written
        assert.ok(await fs.pathExists(outputPath));

        // Verify file content matches return value
        const content = await fs.readFile(outputPath, 'utf8');
        const parsed = JSON.parse(content);
        // Compare key fields (ignore undefined errors field)
        assert.strictEqual(parsed.totalFiles, mapping.totalFiles);
        assert.strictEqual(parsed.successfulMappings, mapping.successfulMappings);
        assert.strictEqual(parsed.mappings.length, mapping.mappings.length);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should use current directory as default repoRoot', async () => {
      const tmpDir = await createTestRepo();
      const originalCwd = process.cwd();
      try {
        process.chdir(tmpDir);
        await createTrackedFile(tmpDir, 'file.txt');

        const fileList = [
          { source: 'file.txt', destination: 'moved.txt' }
        ];

        const outputPath = path.join(tmpDir, 'mapping.json');
        const mapping = await generateAndWriteMapping(fileList, outputPath);

        // Normalize paths for comparison (macOS /private/var vs /var)
        const normalizedRepoRoot = await fs.realpath(mapping.repoRoot);
        const normalizedTmpDir = await fs.realpath(tmpDir);
        assert.strictEqual(normalizedRepoRoot, normalizedTmpDir);
        assert.ok(await fs.pathExists(outputPath));
      } finally {
        process.chdir(originalCwd);
        await fs.remove(tmpDir);
      }
    });
  });

  describe('readMigrationMapping', () => {
    it('should read mapping from JSON file', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'mapping-read-test-'));
      try {
        const mapping = {
          version: '1.0.0',
          generatedAt: new Date().toISOString(),
          totalFiles: 1,
          mappings: [
            {
              oldPath: 'old.txt',
              newPath: 'new.txt',
              size: 100,
              lastModified: new Date().toISOString(),
              gitCommit: 'abc123'
            }
          ]
        };

        const filePath = path.join(tmpDir, 'mapping.json');
        await fs.writeFile(filePath, JSON.stringify(mapping), 'utf8');

        const read = await readMigrationMapping(filePath);
        assert.deepStrictEqual(read, mapping);
      } finally {
        await fs.remove(tmpDir);
      }
    });

    it('should throw error for non-existent file', async () => {
      await assert.rejects(
        async () => {
          await readMigrationMapping('/nonexistent/mapping.json');
        },
        {
          message: /not found/
        }
      );
    });

    it('should throw error for invalid JSON', async () => {
      const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'mapping-read-test-'));
      try {
        const filePath = path.join(tmpDir, 'invalid.json');
        await fs.writeFile(filePath, 'not valid json', 'utf8');

        await assert.rejects(
          async () => {
            await readMigrationMapping(filePath);
          },
          {
            name: 'SyntaxError'
          }
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });

  describe('lookupNewPath', () => {
    it('should find new path for old path', () => {
      const mapping = {
        mappings: [
          { oldPath: 'old1.txt', newPath: 'new1.txt' },
          { oldPath: 'old2.txt', newPath: 'new2.txt' },
          { oldPath: 'old3.txt', newPath: 'new3.txt' }
        ]
      };

      assert.strictEqual(lookupNewPath(mapping, 'old1.txt'), 'new1.txt');
      assert.strictEqual(lookupNewPath(mapping, 'old2.txt'), 'new2.txt');
      assert.strictEqual(lookupNewPath(mapping, 'old3.txt'), 'new3.txt');
    });

    it('should return null for non-existent old path', () => {
      const mapping = {
        mappings: [
          { oldPath: 'old1.txt', newPath: 'new1.txt' }
        ]
      };

      assert.strictEqual(lookupNewPath(mapping, 'nonexistent.txt'), null);
    });

    it('should return null for invalid mapping', () => {
      assert.strictEqual(lookupNewPath(null, 'old.txt'), null);
      assert.strictEqual(lookupNewPath({}, 'old.txt'), null);
      assert.strictEqual(lookupNewPath({ mappings: null }, 'old.txt'), null);
    });

    it('should handle paths with special characters', () => {
      const mapping = {
        mappings: [
          { oldPath: 'path/with spaces.txt', newPath: 'new-path.txt' },
          { oldPath: 'path/with-dashes.txt', newPath: 'new_path.txt' }
        ]
      };

      assert.strictEqual(lookupNewPath(mapping, 'path/with spaces.txt'), 'new-path.txt');
      assert.strictEqual(lookupNewPath(mapping, 'path/with-dashes.txt'), 'new_path.txt');
    });
  });

  describe('lookupOldPath', () => {
    it('should find old path for new path', () => {
      const mapping = {
        mappings: [
          { oldPath: 'old1.txt', newPath: 'new1.txt' },
          { oldPath: 'old2.txt', newPath: 'new2.txt' },
          { oldPath: 'old3.txt', newPath: 'new3.txt' }
        ]
      };

      assert.strictEqual(lookupOldPath(mapping, 'new1.txt'), 'old1.txt');
      assert.strictEqual(lookupOldPath(mapping, 'new2.txt'), 'old2.txt');
      assert.strictEqual(lookupOldPath(mapping, 'new3.txt'), 'old3.txt');
    });

    it('should return null for non-existent new path', () => {
      const mapping = {
        mappings: [
          { oldPath: 'old1.txt', newPath: 'new1.txt' }
        ]
      };

      assert.strictEqual(lookupOldPath(mapping, 'nonexistent.txt'), null);
    });

    it('should return null for invalid mapping', () => {
      assert.strictEqual(lookupOldPath(null, 'new.txt'), null);
      assert.strictEqual(lookupOldPath({}, 'new.txt'), null);
      assert.strictEqual(lookupOldPath({ mappings: null }, 'new.txt'), null);
    });

    it('should handle paths with special characters', () => {
      const mapping = {
        mappings: [
          { oldPath: 'old-path.txt', newPath: 'path/with spaces.txt' },
          { oldPath: 'old_path.txt', newPath: 'path/with-dashes.txt' }
        ]
      };

      assert.strictEqual(lookupOldPath(mapping, 'path/with spaces.txt'), 'old-path.txt');
      assert.strictEqual(lookupOldPath(mapping, 'path/with-dashes.txt'), 'old_path.txt');
    });
  });

  describe('Integration', () => {
    it('should handle complete workflow', async () => {
      const tmpDir = await createTestRepo();
      try {
        // Create test files
        await createTrackedFile(tmpDir, 'docs/guide1.md', 'Guide 1 content');
        await createTrackedFile(tmpDir, 'docs/guide2.md', 'Guide 2 content');
        await createTrackedFile(tmpDir, 'plan/spec.md', 'Spec content');

        const fileList = [
          { source: 'docs/guide1.md', destination: 'new-docs/guides/guide1.md' },
          { source: 'docs/guide2.md', destination: 'new-docs/guides/guide2.md' },
          { source: 'plan/spec.md', destination: 'new-docs/plans/spec.md' }
        ];

        // Generate and write mapping
        const outputPath = path.join(tmpDir, 'migration-mapping.json');
        const mapping = await generateAndWriteMapping(fileList, outputPath, {
          repoRoot: tmpDir
        });

        // Verify mapping structure
        assert.strictEqual(mapping.totalFiles, 3);
        assert.strictEqual(mapping.successfulMappings, 3);
        assert.strictEqual(mapping.mappings.length, 3);

        // Verify all mappings have metadata
        mapping.mappings.forEach((entry) => {
          assert.ok(entry.oldPath);
          assert.ok(entry.newPath);
          assert.strictEqual(typeof entry.size, 'number');
          assert.ok(entry.size > 0);
          assert.ok(entry.lastModified);
          assert.ok(entry.gitCommit);
          assert.strictEqual(entry.gitCommit.length, 40);
        });

        // Read mapping back
        const readMapping = await readMigrationMapping(outputPath);
        // Compare key fields (ignore undefined errors field and path differences)
        assert.strictEqual(readMapping.totalFiles, mapping.totalFiles);
        assert.strictEqual(readMapping.successfulMappings, mapping.successfulMappings);
        assert.strictEqual(readMapping.mappings.length, mapping.mappings.length);

        // Test lookups
        assert.strictEqual(
          lookupNewPath(readMapping, 'docs/guide1.md'),
          'new-docs/guides/guide1.md'
        );
        assert.strictEqual(
          lookupOldPath(readMapping, 'new-docs/plans/spec.md'),
          'plan/spec.md'
        );
      } finally {
        await fs.remove(tmpDir);
      }
    });
  });
});

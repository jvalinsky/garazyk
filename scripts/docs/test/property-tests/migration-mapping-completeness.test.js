/**
 * Property-Based Test: Migration Mapping Completeness
 *
 * **Validates: Requirements 1.5**
 *
 * Property 5: Migration Mapping Completeness
 * For any file moved during consolidation, the migration mapping file should
 * contain an entry mapping the old path to the new path.
 *
 * This test generates random file sets, executes migration mapping generation,
 * and verifies all moved files appear in the mapping with correct old/new paths.
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import { execSync } from "child_process";
import fs from "fs-extra";
import path from "path";
import os from "os";
import crypto from "crypto";
import {
  generateMigrationMapping,
  lookupNewPath,
  lookupOldPath,
} from "../../lib/migration-mapping.js";

/**
 * Creates a temporary git repository for testing
 */
async function createTestRepo() {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "mapping-completeness-test-"));

  // Initialize git repo
  execSync("git init", { cwd: tmpDir, stdio: "pipe" });
  execSync('git config user.email "test@example.com"', { cwd: tmpDir, stdio: "pipe" });
  execSync('git config user.name "Test User"', { cwd: tmpDir, stdio: "pipe" });

  return tmpDir;
}

/**
 * Generates random file content
 */
function generateRandomContent(minSize = 10, maxSize = 1000) {
  const size = Math.floor(Math.random() * (maxSize - minSize + 1)) + minSize;
  return crypto.randomBytes(size).toString("hex");
}

/**
 * Generates a random file structure with source and destination paths
 * @param {number} fileCount - Number of files to generate
 * @param {number} maxDepth - Maximum directory depth
 * @returns {Array<{source: string, destination: string, content: string}>} Array of file descriptors
 */
function generateRandomMigrationPlan(fileCount, maxDepth = 3) {
  const files = [];
  const extensions = [".md", ".txt", ".json", ".yaml"];
  const sourceDirs = ["plan", "plans", "old-docs"];
  const destDirs = ["docs/plans", "docs/guides", "docs/archive"];

  for (let i = 0; i < fileCount; i++) {
    // Generate random source directory depth
    const sourceDepth = Math.floor(Math.random() * (maxDepth + 1));
    const sourcePathParts = [sourceDirs[Math.floor(Math.random() * sourceDirs.length)]];

    for (let d = 0; d < sourceDepth; d++) {
      sourcePathParts.push(`dir${Math.floor(Math.random() * 5)}`);
    }

    // Generate random destination directory depth
    const destDepth = Math.floor(Math.random() * (maxDepth + 1));
    const destPathParts = [destDirs[Math.floor(Math.random() * destDirs.length)]];

    for (let d = 0; d < destDepth; d++) {
      destPathParts.push(`subdir${Math.floor(Math.random() * 5)}`);
    }

    // Generate filename
    const ext = extensions[Math.floor(Math.random() * extensions.length)];
    const filename = `file${i}${ext}`;

    files.push({
      source: path.join(...sourcePathParts, filename),
      destination: path.join(...destPathParts, filename),
      content: generateRandomContent(),
    });
  }

  return files;
}

/**
 * Creates files in repository and commits them
 */
async function createFilesInRepo(repoDir, files) {
  for (const file of files) {
    const fullPath = path.join(repoDir, file.source);
    await fs.ensureDir(path.dirname(fullPath));
    await fs.writeFile(fullPath, file.content, "utf8");
  }

  // Add and commit all files
  execSync("git add .", { cwd: repoDir, stdio: "pipe" });
  execSync('git commit -m "Add test files"', { cwd: repoDir, stdio: "pipe" });
}

/**
 * Verifies that all moved files appear in the migration mapping
 */
function verifyMappingCompleteness(mapping, expectedFiles) {
  const results = {
    total: expectedFiles.length,
    found: 0,
    missing: [],
    incorrectMapping: [],
  };

  for (const file of expectedFiles) {
    // Check if old path exists in mapping
    const mappedNewPath = lookupNewPath(mapping, file.source);

    if (mappedNewPath === null) {
      results.missing.push(file.source);
      continue;
    }

    results.found++;

    // Verify the mapping is correct
    if (mappedNewPath !== file.destination) {
      results.incorrectMapping.push({
        source: file.source,
        expected: file.destination,
        actual: mappedNewPath,
      });
    }

    // Verify reverse lookup works
    const mappedOldPath = lookupOldPath(mapping, file.destination);
    if (mappedOldPath !== file.source) {
      results.incorrectMapping.push({
        destination: file.destination,
        expectedSource: file.source,
        actualSource: mappedOldPath,
      });
    }
  }

  return results;
}

describe("Property Test: Migration Mapping Completeness", () => {
  it("should include all moved files in migration mapping (100 iterations)", async () => {
    const iterations = 100;
    let passedIterations = 0;

    for (let i = 0; i < iterations; i++) {
      const repoDir = await createTestRepo();

      try {
        // Generate random migration plan (1-20 files per iteration)
        const fileCount = Math.floor(Math.random() * 20) + 1;
        const files = generateRandomMigrationPlan(fileCount);

        // Create files in repository
        await createFilesInRepo(repoDir, files);

        // Build file list for migration mapping
        const fileList = files.map((f) => ({
          source: f.source,
          destination: f.destination,
        }));

        // Generate migration mapping
        const mapping = await generateMigrationMapping(fileList, repoDir);

        // Verify all files appear in mapping
        const verification = verifyMappingCompleteness(mapping, files);

        // Assert completeness
        assert.strictEqual(
          verification.missing.length,
          0,
          `Iteration ${i + 1}: Missing files in mapping: ${verification.missing.join(", ")}`,
        );

        assert.strictEqual(
          verification.incorrectMapping.length,
          0,
          `Iteration ${i + 1}: Incorrect mappings: ${
            JSON.stringify(verification.incorrectMapping)
          }`,
        );

        assert.strictEqual(
          verification.found,
          verification.total,
          `Iteration ${
            i + 1
          }: Expected ${verification.total} files in mapping, found ${verification.found}`,
        );

        // Verify mapping metadata
        assert.strictEqual(
          mapping.totalFiles,
          fileCount,
          `Iteration ${i + 1}: Mapping totalFiles should match file count`,
        );

        assert.strictEqual(
          mapping.successfulMappings,
          fileCount,
          `Iteration ${i + 1}: All mappings should be successful`,
        );

        assert.strictEqual(
          mapping.mappings.length,
          fileCount,
          `Iteration ${i + 1}: Mappings array length should match file count`,
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
      `Expected all ${iterations} iterations to pass, but only ${passedIterations} passed`,
    );
  });

  it("should handle empty file list", async () => {
    const repoDir = await createTestRepo();

    try {
      const fileList = [];
      const mapping = await generateMigrationMapping(fileList, repoDir);

      assert.strictEqual(mapping.totalFiles, 0, "Total files should be 0");
      assert.strictEqual(mapping.successfulMappings, 0, "Successful mappings should be 0");
      assert.strictEqual(mapping.mappings.length, 0, "Mappings array should be empty");
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should include metadata for all mapped files", async () => {
    const repoDir = await createTestRepo();

    try {
      // Generate files with varying sizes
      const files = [
        { source: "plan/small.md", destination: "docs/small.md", content: "small" },
        { source: "plan/medium.md", destination: "docs/medium.md", content: "a".repeat(1000) },
        { source: "plan/large.md", destination: "docs/large.md", content: "b".repeat(10000) },
      ];

      await createFilesInRepo(repoDir, files);

      const fileList = files.map((f) => ({
        source: f.source,
        destination: f.destination,
      }));

      const mapping = await generateMigrationMapping(fileList, repoDir);

      // Verify each mapping has complete metadata
      for (const entry of mapping.mappings) {
        assert.ok(entry.oldPath, "Entry should have oldPath");
        assert.ok(entry.newPath, "Entry should have newPath");
        assert.strictEqual(typeof entry.size, "number", "Entry should have numeric size");
        assert.ok(entry.size > 0, "Entry size should be positive");
        assert.ok(entry.lastModified, "Entry should have lastModified timestamp");
        assert.ok(entry.gitCommit, "Entry should have gitCommit hash");
        assert.strictEqual(entry.gitCommit.length, 40, "Git commit should be 40-character SHA-1");
      }
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should handle files with special characters in paths", async () => {
    const repoDir = await createTestRepo();

    try {
      const files = [
        {
          source: "plan/file-with-dashes.md",
          destination: "docs/file-with-dashes.md",
          content: "content1",
        },
        {
          source: "plan/file_with_underscores.md",
          destination: "docs/file_with_underscores.md",
          content: "content2",
        },
        {
          source: "plan/file.with.dots.md",
          destination: "docs/file.with.dots.md",
          content: "content3",
        },
        {
          source: "plan/file with spaces.md",
          destination: "docs/file with spaces.md",
          content: "content4",
        },
      ];

      await createFilesInRepo(repoDir, files);

      const fileList = files.map((f) => ({
        source: f.source,
        destination: f.destination,
      }));

      const mapping = await generateMigrationMapping(fileList, repoDir);

      // Verify all files are in mapping
      const verification = verifyMappingCompleteness(mapping, files);

      assert.strictEqual(verification.missing.length, 0, "No files should be missing from mapping");
      assert.strictEqual(verification.incorrectMapping.length, 0, "No incorrect mappings");
      assert.strictEqual(verification.found, files.length, "All files should be found in mapping");
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should handle deeply nested directory structures", async () => {
    const repoDir = await createTestRepo();

    try {
      const files = [
        {
          source: "plan/a/b/c/d/e/deep.md",
          destination: "docs/x/y/z/deep.md",
          content: "deep content",
        },
        {
          source: "plans/level1/level2/level3/nested.md",
          destination: "docs/guides/section/subsection/nested.md",
          content: "nested content",
        },
      ];

      await createFilesInRepo(repoDir, files);

      const fileList = files.map((f) => ({
        source: f.source,
        destination: f.destination,
      }));

      const mapping = await generateMigrationMapping(fileList, repoDir);

      // Verify all files are in mapping with correct paths
      const verification = verifyMappingCompleteness(mapping, files);

      assert.strictEqual(verification.missing.length, 0, "No files should be missing");
      assert.strictEqual(verification.incorrectMapping.length, 0, "No incorrect mappings");
      assert.strictEqual(verification.found, files.length, "All files should be found");
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should maintain bidirectional lookup capability", async () => {
    const repoDir = await createTestRepo();

    try {
      const files = generateRandomMigrationPlan(10);
      await createFilesInRepo(repoDir, files);

      const fileList = files.map((f) => ({
        source: f.source,
        destination: f.destination,
      }));

      const mapping = await generateMigrationMapping(fileList, repoDir);

      // Verify bidirectional lookups work for all files
      for (const file of files) {
        const newPath = lookupNewPath(mapping, file.source);
        assert.strictEqual(
          newPath,
          file.destination,
          `Forward lookup failed for ${file.source}`,
        );

        const oldPath = lookupOldPath(mapping, file.destination);
        assert.strictEqual(
          oldPath,
          file.source,
          `Reverse lookup failed for ${file.destination}`,
        );
      }
    } finally {
      await fs.remove(repoDir);
    }
  });

  it("should include version and timestamp in mapping", async () => {
    const repoDir = await createTestRepo();

    try {
      const files = [{ source: "plan/test.md", destination: "docs/test.md", content: "test" }];
      await createFilesInRepo(repoDir, files);

      const fileList = files.map((f) => ({
        source: f.source,
        destination: f.destination,
      }));

      const before = new Date();
      const mapping = await generateMigrationMapping(fileList, repoDir);
      const after = new Date();

      // Verify version
      assert.strictEqual(mapping.version, "1.0.0", "Mapping should have version 1.0.0");

      // Verify timestamp
      assert.ok(mapping.generatedAt, "Mapping should have generatedAt timestamp");
      const generatedAt = new Date(mapping.generatedAt);
      assert.ok(generatedAt >= before, "Timestamp should be after test start");
      assert.ok(generatedAt <= after, "Timestamp should be before test end");

      // Verify repoRoot
      assert.ok(mapping.repoRoot, "Mapping should have repoRoot");
    } finally {
      await fs.remove(repoDir);
    }
  });
});

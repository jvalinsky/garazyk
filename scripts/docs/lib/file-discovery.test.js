/**
 * Tests for file discovery and filtering
 */

import { test } from "node:test";
import assert from "node:assert";
import fs from "fs-extra";
import path from "path";
import { fileURLToPath } from "url";
import {
  discoverFiles,
  discoverFilesForMigrations,
  findEmptyDirectories,
  isDirectoryEmpty,
} from "./file-discovery.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Test fixture directory
const testRoot = path.join(__dirname, "../test-fixtures/file-discovery");

/**
 * Creates a test directory structure
 */
async function createTestStructure() {
  await fs.ensureDir(testRoot);

  // Create directory structure
  await fs.ensureDir(path.join(testRoot, "source"));
  await fs.ensureDir(path.join(testRoot, "source/docs"));
  await fs.ensureDir(path.join(testRoot, "source/docs/guides"));
  await fs.ensureDir(path.join(testRoot, "source/images"));
  await fs.ensureDir(path.join(testRoot, "source/.git"));
  await fs.ensureDir(path.join(testRoot, "source/node_modules"));
  await fs.ensureDir(path.join(testRoot, "empty"));
  await fs.ensureDir(path.join(testRoot, "empty/subdir"));

  // Create files
  await fs.writeFile(path.join(testRoot, "source/README.md"), "# Test");
  await fs.writeFile(path.join(testRoot, "source/docs/guide.md"), "# Guide");
  await fs.writeFile(path.join(testRoot, "source/docs/guides/advanced.md"), "# Advanced");
  await fs.writeFile(path.join(testRoot, "source/images/logo.png"), "fake image");
  await fs.writeFile(path.join(testRoot, "source/.DS_Store"), "mac metadata");
  await fs.writeFile(path.join(testRoot, "source/.git/config"), "git config");
  await fs.writeFile(path.join(testRoot, "source/node_modules/package.json"), "{}");
  await fs.writeFile(path.join(testRoot, "source/docs/.hidden"), "hidden file");
}

/**
 * Cleans up test directory
 */
async function cleanupTestStructure() {
  await fs.remove(testRoot);
}

test("discoverFiles returns empty array for non-existent directory", async () => {
  const files = await discoverFiles("nonexistent", { repoRoot: testRoot });
  assert.deepStrictEqual(files, []);
});

test("discoverFiles finds all files with default patterns", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", { repoRoot: testRoot });

    // Should include markdown and image files
    assert.ok(files.includes("README.md"));
    assert.ok(files.includes("docs/guide.md"));
    assert.ok(files.includes("docs/guides/advanced.md"));
    assert.ok(files.includes("images/logo.png"));
    assert.ok(files.includes("docs/.hidden"));

    // Should exclude .git, node_modules, .DS_Store by default
    assert.ok(!files.some((f) => f.includes(".git")));
    assert.ok(!files.some((f) => f.includes("node_modules")));
    assert.ok(!files.includes(".DS_Store"));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles respects filePatterns for markdown only", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", {
      filePatterns: ["**/*.md"],
      repoRoot: testRoot,
    });

    // Should include only markdown files
    assert.ok(files.includes("README.md"));
    assert.ok(files.includes("docs/guide.md"));
    assert.ok(files.includes("docs/guides/advanced.md"));

    // Should not include non-markdown files
    assert.ok(!files.includes("images/logo.png"));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles respects multiple filePatterns", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", {
      filePatterns: ["**/*.md", "**/*.png"],
      repoRoot: testRoot,
    });

    // Should include markdown and png files
    assert.ok(files.includes("README.md"));
    assert.ok(files.includes("images/logo.png"));

    // Should not include hidden files
    assert.ok(!files.includes("docs/.hidden"));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles respects custom excludePatterns", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", {
      excludePatterns: ["**/docs/**"],
      repoRoot: testRoot,
    });

    // Should include root files
    assert.ok(files.includes("README.md"));
    assert.ok(files.includes("images/logo.png"));

    // Should exclude docs directory
    assert.ok(!files.some((f) => f.startsWith("docs/")));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles handles dotfiles with dot option", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", {
      filePatterns: ["**/*"],
      excludePatterns: ["**/.git/**", "**/node_modules/**"],
      repoRoot: testRoot,
    });

    // Should include dotfiles
    assert.ok(files.includes(".DS_Store"));
    assert.ok(files.includes("docs/.hidden"));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles uses forward slashes in paths", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", { repoRoot: testRoot });

    // All paths should use forward slashes
    files.forEach((file) => {
      assert.ok(!file.includes("\\"), `Path should not contain backslashes: ${file}`);
    });
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFilesForMigrations handles multiple migrations", async () => {
  await createTestStructure();

  try {
    const migrations = [
      {
        source: "source",
        destination: "dest1",
        filePatterns: ["**/*.md"],
        excludePatterns: ["**/.git/**"],
      },
      {
        source: "empty",
        destination: "dest2",
        filePatterns: ["**/*"],
        excludePatterns: [],
      },
    ];

    const fileMap = await discoverFilesForMigrations(migrations, testRoot);

    assert.strictEqual(fileMap.size, 2);
    assert.ok(fileMap.has("source"));
    assert.ok(fileMap.has("empty"));

    const sourceFiles = fileMap.get("source");
    assert.ok(sourceFiles.length > 0);
    assert.ok(sourceFiles.every((f) => f.endsWith(".md")));

    const emptyFiles = fileMap.get("empty");
    assert.strictEqual(emptyFiles.length, 0);
  } finally {
    await cleanupTestStructure();
  }
});

test("isDirectoryEmpty returns true for empty directory", async () => {
  await createTestStructure();

  try {
    const isEmpty = await isDirectoryEmpty("empty", { repoRoot: testRoot });
    assert.strictEqual(isEmpty, true);
  } finally {
    await cleanupTestStructure();
  }
});

test("isDirectoryEmpty returns false for non-empty directory", async () => {
  await createTestStructure();

  try {
    const isEmpty = await isDirectoryEmpty("source", { repoRoot: testRoot });
    assert.strictEqual(isEmpty, false);
  } finally {
    await cleanupTestStructure();
  }
});

test("isDirectoryEmpty returns true for non-existent directory", async () => {
  const isEmpty = await isDirectoryEmpty("nonexistent", { repoRoot: testRoot });
  assert.strictEqual(isEmpty, true);
});

test("isDirectoryEmpty ignores .git directory", async () => {
  await createTestStructure();

  try {
    // Create a directory with only .git
    const gitOnlyDir = path.join(testRoot, "git-only");
    await fs.ensureDir(path.join(gitOnlyDir, ".git"));
    await fs.writeFile(path.join(gitOnlyDir, ".git/config"), "config");

    const isEmpty = await isDirectoryEmpty("git-only", { repoRoot: testRoot });
    assert.strictEqual(isEmpty, true);
  } finally {
    await cleanupTestStructure();
  }
});

test("findEmptyDirectories finds all empty subdirectories", async () => {
  await createTestStructure();

  try {
    const emptyDirs = await findEmptyDirectories("empty", { repoRoot: testRoot });

    // Should find the empty subdirectory
    assert.ok(emptyDirs.includes(path.join("empty", "subdir")));
  } finally {
    await cleanupTestStructure();
  }
});

test("findEmptyDirectories returns empty array for non-existent directory", async () => {
  const emptyDirs = await findEmptyDirectories("nonexistent", { repoRoot: testRoot });
  assert.deepStrictEqual(emptyDirs, []);
});

test("findEmptyDirectories sorts by depth (deepest first)", async () => {
  await createTestStructure();

  try {
    // Create nested empty directories
    await fs.ensureDir(path.join(testRoot, "nested/level1/level2/level3"));

    const emptyDirs = await findEmptyDirectories("nested", { repoRoot: testRoot });

    // Should be sorted deepest first
    for (let i = 0; i < emptyDirs.length - 1; i++) {
      const depthCurrent = emptyDirs[i].split(path.sep).length;
      const depthNext = emptyDirs[i + 1].split(path.sep).length;
      assert.ok(depthCurrent >= depthNext, "Directories should be sorted deepest first");
    }
  } finally {
    await cleanupTestStructure();
  }
});

test("findEmptyDirectories excludes .git directories", async () => {
  await createTestStructure();

  try {
    const emptyDirs = await findEmptyDirectories("source", { repoRoot: testRoot });

    // Should not include .git directory
    assert.ok(!emptyDirs.some((d) => d.includes(".git")));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles handles special characters in filenames", async () => {
  await createTestStructure();

  try {
    // Create files with special characters
    await fs.writeFile(path.join(testRoot, "source/file with spaces.md"), "content");
    await fs.writeFile(path.join(testRoot, "source/file-with-dashes.md"), "content");
    await fs.writeFile(path.join(testRoot, "source/file_with_underscores.md"), "content");

    const files = await discoverFiles("source", {
      filePatterns: ["**/*.md"],
      repoRoot: testRoot,
    });

    assert.ok(files.includes("file with spaces.md"));
    assert.ok(files.includes("file-with-dashes.md"));
    assert.ok(files.includes("file_with_underscores.md"));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles handles deeply nested directories", async () => {
  await createTestStructure();

  try {
    // Create deeply nested structure
    const deepPath = path.join(testRoot, "source/a/b/c/d/e/f");
    await fs.ensureDir(deepPath);
    await fs.writeFile(path.join(deepPath, "deep.md"), "deep content");

    const files = await discoverFiles("source", {
      filePatterns: ["**/*.md"],
      repoRoot: testRoot,
    });

    assert.ok(files.includes("a/b/c/d/e/f/deep.md"));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles handles empty filePatterns array", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", {
      filePatterns: [],
      repoRoot: testRoot,
    });

    // Empty patterns should match all files (except excluded)
    assert.ok(files.length > 0);
    assert.ok(files.includes("README.md"));
  } finally {
    await cleanupTestStructure();
  }
});

test("discoverFiles handles pattern with leading slash", async () => {
  await createTestStructure();

  try {
    const files = await discoverFiles("source", {
      filePatterns: ["*.md"], // Only root level markdown files
      repoRoot: testRoot,
    });

    // Should include root level markdown
    assert.ok(files.includes("README.md"));

    // Should not include nested markdown
    assert.ok(!files.includes("docs/guide.md"));
  } finally {
    await cleanupTestStructure();
  }
});

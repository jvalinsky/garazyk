/**
 * Property-Based Test: Empty Directory Cleanup
 *
 * **Validates: Requirements 1.3**
 *
 * Property 4: Empty Directory Cleanup
 * After moving all files out of a source directory tree, running the cleanup
 * should remove all empty directories (including the root when configured).
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import fs from "fs-extra";
import path from "path";
import os from "os";
import crypto from "crypto";
import { discoverFiles } from "../../lib/file-discovery.js";
import { removeEmptyDirectories } from "../../lib/directory-cleanup.js";

function generateRandomContent(minSize = 10, maxSize = 200) {
  const size = Math.floor(Math.random() * (maxSize - minSize + 1)) + minSize;
  return crypto.randomBytes(size).toString("hex");
}

function generateRandomPaths(fileCount, maxDepth = 4) {
  const files = [];
  const extensions = [".md", ".txt", ".json"];

  for (let i = 0; i < fileCount; i++) {
    const depth = Math.floor(Math.random() * (maxDepth + 1));
    const parts = [];

    for (let d = 0; d < depth; d++) {
      parts.push(`dir${Math.floor(Math.random() * 5)}`);
    }

    const ext = extensions[Math.floor(Math.random() * extensions.length)];
    parts.push(`file${i}${ext}`);

    files.push(parts.join("/"));
  }

  return files;
}

async function createFiles(baseDir, rootDir, files) {
  for (const rel of files) {
    const full = path.join(baseDir, rootDir, rel);
    await fs.ensureDir(path.dirname(full));
    await fs.writeFile(full, generateRandomContent(), "utf8");
  }
}

async function moveAllFiles(baseDir, sourceDir, destDir) {
  const files = await discoverFiles(sourceDir, {
    filePatterns: ["**/*"],
    excludePatterns: ["**/.git/**"],
    repoRoot: baseDir,
  });

  for (const rel of files) {
    const from = path.join(baseDir, sourceDir, rel);
    const to = path.join(baseDir, destDir, rel);
    await fs.ensureDir(path.dirname(to));
    await fs.move(from, to, { overwrite: true });
  }
}

describe("Property Test: Empty Directory Cleanup", () => {
  it("should remove all empty directories after files are moved (100 iterations)", async () => {
    const iterations = 100;

    for (let i = 0; i < iterations; i++) {
      const repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), "empty-cleanup-prop-"));

      try {
        const fileCount = Math.floor(Math.random() * 15) + 1;
        const files = generateRandomPaths(fileCount);

        await createFiles(repoRoot, "source", files);
        await moveAllFiles(repoRoot, "source", "dest");

        const result = await removeEmptyDirectories("source", {
          repoRoot,
          removeRoot: true,
        });

        assert.ok(result.removed.includes("source"));
        assert.strictEqual(await fs.pathExists(path.join(repoRoot, "source")), false);

        const movedFiles = await discoverFiles("dest", {
          filePatterns: ["**/*"],
          excludePatterns: [],
          repoRoot,
        });
        assert.strictEqual(movedFiles.length, files.length);
      } finally {
        await fs.remove(repoRoot);
      }
    }
  });
});

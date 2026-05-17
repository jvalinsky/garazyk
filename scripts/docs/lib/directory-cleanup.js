/**
 * Directory Cleanup
 *
 * Removes empty directories after a migration has moved files out of them.
 * Designed to be safe-by-default: it re-checks emptiness before deletion,
 * deletes from deepest to shallowest, and supports dry-run mode.
 */

import fs from "fs-extra";
import path from "path";
import { findEmptyDirectories, isDirectoryEmpty } from "./file-discovery.js";

/**
 * Removes empty directories within a directory tree.
 *
 * @param {string} rootDir - Root directory to clean (relative to repo root)
 * @param {Object} options - Cleanup options
 * @param {Array<string>} options.excludePatterns - Exclusion patterns (e.g. "**\/.git\/**")
 * @param {string} options.repoRoot - Repository root (absolute path)
 * @param {boolean} options.dryRun - If true, do not delete anything
 * @param {boolean} options.removeRoot - If true, remove rootDir if it becomes empty
 * @param {(dir: string) => void} options.onRemove - Callback invoked for each removed directory
 * @returns {Promise<{candidates: Array<string>, removed: Array<string>, skipped: Array<{dir: string, reason: string}>}>}
 */
export async function removeEmptyDirectories(rootDir, options = {}) {
  const {
    excludePatterns = ["**/.git/**"],
    repoRoot = process.cwd(),
    dryRun = false,
    removeRoot = false,
    onRemove,
  } = options;

  const candidates = await findEmptyDirectories(rootDir, {
    excludePatterns,
    repoRoot,
  });

  const removed = [];
  const skipped = [];

  for (const dir of candidates) {
    const stillEmpty = await isDirectoryEmpty(dir, { excludePatterns, repoRoot });
    if (!stillEmpty) {
      skipped.push({ dir, reason: "not empty" });
      continue;
    }

    if (!dryRun) {
      const absDir = path.resolve(repoRoot, dir);
      if (!await fs.pathExists(absDir)) {
        skipped.push({ dir, reason: "missing" });
        continue;
      }
      const entries = await fs.readdir(absDir);
      if (entries.length > 0) {
        skipped.push({ dir, reason: "not physically empty" });
        continue;
      }
      await fs.rmdir(absDir);
    }

    removed.push(dir);
    if (onRemove) {
      onRemove(dir);
    }
  }

  if (removeRoot) {
    const absRoot = path.resolve(repoRoot, rootDir);
    if (!await fs.pathExists(absRoot)) {
      skipped.push({ dir: rootDir, reason: "missing" });
      return { candidates, removed, skipped };
    }

    const rootEmpty = await isDirectoryEmpty(rootDir, { excludePatterns, repoRoot });
    if (rootEmpty) {
      if (!dryRun) {
        const entries = await fs.readdir(absRoot);
        if (entries.length > 0) {
          skipped.push({ dir: rootDir, reason: "not physically empty" });
          return { candidates, removed, skipped };
        }
        await fs.rmdir(absRoot);
      }
      removed.push(rootDir);
      if (onRemove) {
        onRemove(rootDir);
      }
    }
  }

  return { candidates, removed, skipped };
}

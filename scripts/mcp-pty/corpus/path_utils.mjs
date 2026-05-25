/**
 * Shared path resolution utilities for the TUI Corpus tools.
 *
 * Used by batch_runner.mjs, edge_runner.mjs, and generator.mjs to
 * resolve binary names to full paths via $PATH or direct file access.
 */

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

/**
 * Resolve a binary name to a full executable path.
 *
 * For absolute/relative paths (containing "/"), checks direct file access.
 * For simple names, searches each directory in $PATH.
 * Falls back to `which` if PATH search fails.
 *
 * @param {string} binary - Binary name or full path
 * @returns {string|null} Resolved full path, or null if not found
 */
export function resolveBinary(binary) {
  if (!binary) return null;

  // Absolute or relative paths: check directly
  if (binary.includes("/")) {
    try {
      fs.accessSync(binary, fs.constants.X_OK);
      return binary;
    } catch {
      return null;
    }
  }

  // Simple name: search $PATH (filter empty entries from trailing colons)
  const pathDirs = (process.env.PATH || "").split(":").filter(d => d.length > 0);
  for (const dir of pathDirs) {
    const fullPath = path.join(dir, binary);
    try {
      fs.accessSync(fullPath, fs.constants.X_OK);
      return fullPath;
    } catch {
      // continue
    }
  }

  // Fallback: try which
  try {
    const result = execSync(`which "${binary}" 2>/dev/null`, { stdio: "pipe" }).toString().trim();
    return result || null;
  } catch {
    return null;
  }
}

/**
 * Check if a binary exists anywhere accessible.
 * @param {string} binary - Binary name or full path
 * @returns {boolean}
 */
export function binaryExists(binary) {
  return resolveBinary(binary) !== null;
}

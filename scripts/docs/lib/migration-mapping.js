/**
 * Migration Mapping Generator
 *
 * Generates a JSON file mapping old file paths to new paths during documentation
 * consolidation. Includes file metadata (size, last modified, git commit) to
 * provide an audit trail and reference for the migration.
 */

import fs from "fs-extra";
import path from "path";
import { execSync } from "child_process";

/**
 * Gets the last git commit hash for a file
 *
 * @param {string} filePath - File path relative to repo root
 * @param {string} repoRoot - Repository root directory
 * @returns {string|null} Commit hash or null if not available
 */
function getLastCommit(filePath, repoRoot) {
  try {
    const output = execSync(
      `git log -1 --format=%H -- "${filePath}"`,
      {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: "pipe",
      },
    );
    return output.trim() || null;
  } catch (error) {
    return null;
  }
}

/**
 * Gets file metadata (size, last modified, git commit)
 *
 * @param {string} filePath - File path relative to repo root
 * @param {string} repoRoot - Repository root directory
 * @returns {Promise<Object>} File metadata object
 */
async function getFileMetadata(filePath, repoRoot) {
  const absolutePath = path.resolve(repoRoot, filePath);

  try {
    const stats = await fs.stat(absolutePath);

    return {
      size: stats.size,
      lastModified: stats.mtime.toISOString(),
      gitCommit: getLastCommit(filePath, repoRoot),
    };
  } catch (error) {
    // File doesn't exist or can't be accessed
    return {
      size: null,
      lastModified: null,
      gitCommit: null,
      error: error.message,
    };
  }
}

/**
 * Generates a migration mapping entry for a single file
 *
 * @param {string} oldPath - Original file path (relative to repo root)
 * @param {string} newPath - New file path (relative to repo root)
 * @param {string} repoRoot - Repository root directory
 * @returns {Promise<Object>} Migration mapping entry
 */
export async function generateMappingEntry(oldPath, newPath, repoRoot = process.cwd()) {
  // Get metadata from the old path (before migration)
  const metadata = await getFileMetadata(oldPath, repoRoot);

  return {
    oldPath,
    newPath,
    ...metadata,
  };
}

/**
 * Generates a complete migration mapping from a file list
 *
 * @param {Array<Object>} fileList - Array of {source, destination} objects
 * @param {string} repoRoot - Repository root directory
 * @returns {Promise<Object>} Migration mapping object
 */
export async function generateMigrationMapping(fileList, repoRoot = process.cwd()) {
  if (!Array.isArray(fileList)) {
    throw new TypeError("fileList must be an array");
  }

  const mappings = [];
  const errors = [];

  for (const file of fileList) {
    if (!file || typeof file !== "object") {
      errors.push({
        file,
        error: "Invalid file entry: must be an object",
      });
      continue;
    }

    if (!file.source || !file.destination) {
      errors.push({
        file,
        error: "Invalid file entry: must have source and destination properties",
      });
      continue;
    }

    try {
      const entry = await generateMappingEntry(
        file.source,
        file.destination,
        repoRoot,
      );
      mappings.push(entry);
    } catch (error) {
      errors.push({
        file,
        error: error.message,
      });
    }
  }

  return {
    version: "1.0.0",
    generatedAt: new Date().toISOString(),
    repoRoot,
    totalFiles: fileList.length,
    successfulMappings: mappings.length,
    failedMappings: errors.length,
    mappings,
    errors: errors.length > 0 ? errors : undefined,
  };
}

/**
 * Writes migration mapping to a JSON file
 *
 * @param {Object} mapping - Migration mapping object
 * @param {string} outputPath - Output file path
 * @returns {Promise<void>}
 */
export async function writeMigrationMapping(mapping, outputPath) {
  if (!mapping || typeof mapping !== "object") {
    throw new TypeError("mapping must be an object");
  }

  if (!outputPath || typeof outputPath !== "string") {
    throw new TypeError("outputPath must be a string");
  }

  // Ensure output directory exists
  const outputDir = path.dirname(outputPath);
  await fs.ensureDir(outputDir);

  // Write mapping as formatted JSON
  await fs.writeFile(
    outputPath,
    JSON.stringify(mapping, null, 2),
    "utf8",
  );
}

/**
 * Generates and writes migration mapping in one operation
 *
 * @param {Array<Object>} fileList - Array of {source, destination} objects
 * @param {string} outputPath - Output file path
 * @param {Object} options - Generation options
 * @param {string} options.repoRoot - Repository root directory
 * @returns {Promise<Object>} Generated migration mapping
 */
export async function generateAndWriteMapping(fileList, outputPath, options = {}) {
  const { repoRoot = process.cwd() } = options;

  const mapping = await generateMigrationMapping(fileList, repoRoot);
  await writeMigrationMapping(mapping, outputPath);

  return mapping;
}

/**
 * Reads a migration mapping from a JSON file
 *
 * @param {string} mappingPath - Path to mapping file
 * @returns {Promise<Object>} Migration mapping object
 */
export async function readMigrationMapping(mappingPath) {
  if (!await fs.pathExists(mappingPath)) {
    throw new Error(`Migration mapping file not found: ${mappingPath}`);
  }

  const content = await fs.readFile(mappingPath, "utf8");
  return JSON.parse(content);
}

/**
 * Looks up the new path for an old path in a migration mapping
 *
 * @param {Object} mapping - Migration mapping object
 * @param {string} oldPath - Old file path to look up
 * @returns {string|null} New path or null if not found
 */
export function lookupNewPath(mapping, oldPath) {
  if (!mapping || !mapping.mappings) {
    return null;
  }

  const entry = mapping.mappings.find((m) => m.oldPath === oldPath);
  return entry ? entry.newPath : null;
}

/**
 * Looks up the old path for a new path in a migration mapping
 *
 * @param {Object} mapping - Migration mapping object
 * @param {string} newPath - New file path to look up
 * @returns {string|null} Old path or null if not found
 */
export function lookupOldPath(mapping, newPath) {
  if (!mapping || !mapping.mappings) {
    return null;
  }

  const entry = mapping.mappings.find((m) => m.newPath === newPath);
  return entry ? entry.oldPath : null;
}

/**
 * Git Operations for Documentation Migration
 *
 * Provides functions to execute git mv commands for preserving file history
 * during documentation migration. Includes batch processing and rollback
 * capabilities for safe migration operations.
 */

import { execSync } from "child_process";
import fs from "fs-extra";
import path from "path";

/**
 * Error class for git operation failures
 */
export class GitOperationError extends Error {
  constructor(message, command = null, stderr = null) {
    super(message);
    this.name = "GitOperationError";
    this.command = command;
    this.stderr = stderr;
  }
}

/**
 * Checks if a directory is a git repository
 *
 * @param {string} dirPath - Directory path to check
 * @returns {boolean} True if directory is a git repository
 */
export function isGitRepository(dirPath = process.cwd()) {
  try {
    execSync("git rev-parse --git-dir", {
      cwd: dirPath,
      stdio: "pipe",
      encoding: "utf8",
    });
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Checks if a file is tracked by git
 *
 * @param {string} filePath - File path relative to repo root
 * @param {string} repoRoot - Repository root directory
 * @returns {boolean} True if file is tracked by git
 */
export function isFileTracked(filePath, repoRoot = process.cwd()) {
  try {
    execSync(`git ls-files --error-unmatch "${filePath}"`, {
      cwd: repoRoot,
      stdio: "pipe",
      encoding: "utf8",
    });
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Executes a single git mv operation
 *
 * @param {string} sourcePath - Source file path (relative to repo root)
 * @param {string} destPath - Destination file path (relative to repo root)
 * @param {Object} options - Operation options
 * @param {string} options.repoRoot - Repository root directory
 * @param {boolean} options.force - Force move even if destination exists
 * @param {boolean} options.dryRun - Perform dry run without actual changes
 * @param {boolean} options.verbose - Enable verbose output
 * @returns {Promise<Object>} Result object with { success, sourcePath, destPath, message }
 */
export async function executeGitMv(sourcePath, destPath, options = {}) {
  const {
    repoRoot = process.cwd(),
    force = false,
    dryRun = false,
    verbose = false,
  } = options;

  // Validate inputs
  if (!sourcePath || !destPath) {
    throw new GitOperationError("Source and destination paths are required");
  }

  // Check if we're in a git repository
  if (!isGitRepository(repoRoot)) {
    throw new GitOperationError(
      `Not a git repository: ${repoRoot}`,
    );
  }

  // Resolve absolute paths
  const absoluteSource = path.resolve(repoRoot, sourcePath);
  const absoluteDest = path.resolve(repoRoot, destPath);

  // Check if source file exists
  if (!await fs.pathExists(absoluteSource)) {
    throw new GitOperationError(
      `Source file does not exist: ${sourcePath}`,
    );
  }

  // Check if source is tracked by git
  if (!isFileTracked(sourcePath, repoRoot)) {
    throw new GitOperationError(
      `Source file is not tracked by git: ${sourcePath}`,
    );
  }

  // Create destination directory if it doesn't exist
  const destDir = path.dirname(absoluteDest);
  if (!dryRun && !await fs.pathExists(destDir)) {
    await fs.ensureDir(destDir);
  }

  // Build git mv command
  const forceFlag = force ? "-f " : "";
  const command = `git mv ${forceFlag}"${sourcePath}" "${destPath}"`;

  if (verbose) {
    console.log(`Executing: ${command}`);
  }

  if (dryRun) {
    return {
      success: true,
      sourcePath,
      destPath,
      message: `[DRY RUN] Would execute: ${command}`,
      dryRun: true,
    };
  }

  // Execute git mv
  try {
    const output = execSync(command, {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: "pipe",
    });

    return {
      success: true,
      sourcePath,
      destPath,
      message: `Successfully moved ${sourcePath} to ${destPath}`,
      output: output.trim(),
    };
  } catch (error) {
    throw new GitOperationError(
      `Failed to execute git mv: ${error.message}`,
      command,
      error.stderr,
    );
  }
}

/**
 * Executes git mv operations for multiple files in batch
 *
 * @param {Array<Object>} fileList - Array of {source, destination} objects
 * @param {Object} options - Operation options
 * @param {string} options.repoRoot - Repository root directory
 * @param {boolean} options.force - Force move even if destination exists
 * @param {boolean} options.dryRun - Perform dry run without actual changes
 * @param {boolean} options.verbose - Enable verbose output
 * @param {boolean} options.continueOnError - Continue processing even if some files fail
 * @param {Function} options.onProgress - Progress callback (current, total, result)
 * @returns {Promise<Object>} Batch result with { success, results, errors, summary }
 */
export async function batchGitMv(fileList, options = {}) {
  const {
    repoRoot = process.cwd(),
    force = false,
    dryRun = false,
    verbose = false,
    continueOnError = false,
    onProgress = null,
  } = options;

  // Validate inputs
  if (!Array.isArray(fileList) || fileList.length === 0) {
    throw new GitOperationError("File list must be a non-empty array");
  }

  // Check if we're in a git repository
  if (!isGitRepository(repoRoot)) {
    throw new GitOperationError(
      `Not a git repository: ${repoRoot}`,
    );
  }

  const results = [];
  const errors = [];
  let successCount = 0;
  let failureCount = 0;
  let skippedCount = 0;

  // Process each file
  for (let i = 0; i < fileList.length; i++) {
    const file = fileList[i];

    // Validate file entry
    if (!file || !file.source || !file.destination) {
      const error = {
        index: i,
        file,
        message: "Invalid file entry: must have source and destination properties",
      };
      errors.push(error);
      failureCount++;

      if (!continueOnError) {
        break;
      }
      continue;
    }

    try {
      const result = await executeGitMv(file.source, file.destination, {
        repoRoot,
        force,
        dryRun,
        verbose,
      });

      results.push(result);

      if (result.success) {
        successCount++;
      } else {
        skippedCount++;
      }

      // Call progress callback
      if (onProgress) {
        onProgress(i + 1, fileList.length, result);
      }
    } catch (error) {
      const errorInfo = {
        index: i,
        file,
        message: error.message,
        command: error.command,
        stderr: error.stderr,
      };
      errors.push(errorInfo);
      failureCount++;

      if (!continueOnError) {
        // Rollback on failure
        if (!dryRun && results.length > 0) {
          if (verbose) {
            console.log("\nError occurred, attempting rollback...");
          }
          await rollbackGitMv(results, { repoRoot, verbose });
        }

        throw new GitOperationError(
          `Batch operation failed at file ${i + 1}/${fileList.length}: ${error.message}`,
          error.command,
          error.stderr,
        );
      }

      // Continue on error
      if (verbose) {
        console.error(`Warning: Failed to move ${file.source}: ${error.message}`);
      }
    }
  }

  const summary = {
    total: fileList.length,
    success: successCount,
    failed: failureCount,
    skipped: skippedCount,
  };

  return {
    success: failureCount === 0,
    results,
    errors,
    summary,
  };
}

/**
 * Rolls back git mv operations by moving files back to their original locations
 *
 * @param {Array<Object>} results - Array of successful operation results
 * @param {Object} options - Rollback options
 * @param {string} options.repoRoot - Repository root directory
 * @param {boolean} options.verbose - Enable verbose output
 * @returns {Promise<Object>} Rollback result with { success, rolledBack, failed }
 */
export async function rollbackGitMv(results, options = {}) {
  const {
    repoRoot = process.cwd(),
    verbose = false,
  } = options;

  // Filter for successful moves only
  const successfulMoves = results.filter((r) => r.success && !r.dryRun);

  if (successfulMoves.length === 0) {
    return {
      success: true,
      rolledBack: 0,
      failed: 0,
      message: "No operations to rollback",
    };
  }

  if (verbose) {
    console.log(`Rolling back ${successfulMoves.length} operations...`);
  }

  let rolledBack = 0;
  let failed = 0;
  const rollbackErrors = [];

  // Rollback in reverse order
  for (let i = successfulMoves.length - 1; i >= 0; i--) {
    const result = successfulMoves[i];

    try {
      // Move file back from destination to source
      const command = `git mv "${result.destPath}" "${result.sourcePath}"`;

      if (verbose) {
        console.log(`Rollback: ${command}`);
      }

      execSync(command, {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: "pipe",
      });

      rolledBack++;
    } catch (error) {
      failed++;
      rollbackErrors.push({
        sourcePath: result.sourcePath,
        destPath: result.destPath,
        message: error.message,
      });

      if (verbose) {
        console.error(`Failed to rollback ${result.destPath}: ${error.message}`);
      }
    }
  }

  return {
    success: failed === 0,
    rolledBack,
    failed,
    errors: rollbackErrors,
  };
}

/**
 * Verifies that git history is preserved after a move operation
 *
 * @param {string} filePath - File path to check (relative to repo root)
 * @param {Object} options - Verification options
 * @param {string} options.repoRoot - Repository root directory
 * @param {number} options.minCommits - Minimum number of commits expected in history
 * @returns {Promise<Object>} Verification result with { preserved, commitCount, history }
 */
export async function verifyHistoryPreservation(filePath, options = {}) {
  const {
    repoRoot = process.cwd(),
    minCommits = 1,
  } = options;

  // Check if file exists
  const absolutePath = path.resolve(repoRoot, filePath);
  if (!await fs.pathExists(absolutePath)) {
    return {
      preserved: false,
      commitCount: 0,
      message: `File does not exist: ${filePath}`,
    };
  }

  // Get git log for the file
  try {
    const output = execSync(
      `git log --follow --oneline -- "${filePath}"`,
      {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: "pipe",
      },
    );

    const commits = output.trim().split("\n").filter((line) => line.length > 0);
    const commitCount = commits.length;

    return {
      preserved: commitCount >= minCommits,
      commitCount,
      history: commits,
      message: commitCount >= minCommits
        ? `History preserved: ${commitCount} commits found`
        : `Insufficient history: ${commitCount} commits (expected at least ${minCommits})`,
    };
  } catch (error) {
    return {
      preserved: false,
      commitCount: 0,
      message: `Failed to retrieve git history: ${error.message}`,
    };
  }
}

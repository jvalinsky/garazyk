/**
 * Migration Report Generator
 *
 * Generates a detailed report of migration execution including statistics,
 * status of all moved files, validation results, and human-readable summary.
 */

import fs from 'fs-extra';
import path from 'path';

/**
 * Generates a migration report from migration results
 *
 * @param {Object} migrationData - Migration execution data
 * @param {Array<Object>} migrationData.movedFiles - Array of moved file objects
 * @param {Array<Object>} migrationData.updatedLinks - Array of link update objects
 * @param {Array<Object>} migrationData.errors - Array of error objects
 * @param {Object} migrationData.validation - Validation results
 * @param {Object} options - Report generation options
 * @param {string} options.repoRoot - Repository root directory
 * @returns {Object} Migration report object
 */
export function generateMigrationReport(migrationData, options = {}) {
  const { repoRoot = process.cwd() } = options;

  if (!migrationData || typeof migrationData !== 'object') {
    throw new TypeError('migrationData must be an object');
  }

  const {
    movedFiles = [],
    updatedLinks = [],
    errors = [],
    validation = {}
  } = migrationData;

  // Calculate statistics
  const stats = {
    totalFilesMoved: movedFiles.length,
    successfulMoves: movedFiles.filter((f) => f.status === 'success').length,
    failedMoves: movedFiles.filter((f) => f.status === 'failed').length,
    totalLinksUpdated: updatedLinks.length,
    totalErrors: errors.length,
    validationPassed: validation.passed === true
  };

  // Categorize errors by type
  const errorsByType = {};
  for (const error of errors) {
    const type = error.type || 'unknown';
    if (!errorsByType[type]) {
      errorsByType[type] = [];
    }
    errorsByType[type].push(error);
  }

  // Generate human-readable summary
  const summary = generateSummary(stats, errorsByType);

  return {
    version: '1.0.0',
    generatedAt: new Date().toISOString(),
    repoRoot,
    statistics: stats,
    movedFiles,
    updatedLinks,
    errors,
    errorsByType,
    validation,
    summary
  };
}

/**
 * Generates a human-readable summary of the migration
 *
 * @param {Object} stats - Migration statistics
 * @param {Object} errorsByType - Errors categorized by type
 * @returns {string} Human-readable summary
 */
function generateSummary(stats, errorsByType) {
  const lines = [];

  lines.push('Migration Summary');
  lines.push('=================');
  lines.push('');

  // Files moved
  lines.push(`Files Moved: ${stats.totalFilesMoved}`);
  lines.push(`  - Successful: ${stats.successfulMoves}`);
  lines.push(`  - Failed: ${stats.failedMoves}`);
  lines.push('');

  // Links updated
  lines.push(`Links Updated: ${stats.totalLinksUpdated}`);
  lines.push('');

  // Errors
  if (stats.totalErrors > 0) {
    lines.push(`Errors: ${stats.totalErrors}`);
    for (const [type, errors] of Object.entries(errorsByType)) {
      lines.push(`  - ${type}: ${errors.length}`);
    }
    lines.push('');
  }

  // Validation
  lines.push(`Validation: ${stats.validationPassed ? 'PASSED' : 'FAILED'}`);
  lines.push('');

  // Overall status
  const overallStatus = stats.failedMoves === 0 && stats.totalErrors === 0 && stats.validationPassed
    ? 'SUCCESS'
    : 'COMPLETED WITH ISSUES';

  lines.push(`Overall Status: ${overallStatus}`);

  return lines.join('\n');
}

/**
 * Writes migration report to a JSON file
 *
 * @param {Object} report - Migration report object
 * @param {string} outputPath - Output file path
 * @returns {Promise<void>}
 */
export async function writeMigrationReport(report, outputPath) {
  if (!report || typeof report !== 'object') {
    throw new TypeError('report must be an object');
  }

  if (!outputPath || typeof outputPath !== 'string') {
    throw new TypeError('outputPath must be a string');
  }

  // Ensure output directory exists
  const outputDir = path.dirname(outputPath);
  await fs.ensureDir(outputDir);

  // Write report as formatted JSON
  await fs.writeFile(
    outputPath,
    JSON.stringify(report, null, 2),
    'utf8'
  );
}

/**
 * Generates and writes migration report in one operation
 *
 * @param {Object} migrationData - Migration execution data
 * @param {string} outputPath - Output file path
 * @param {Object} options - Generation options
 * @returns {Promise<Object>} Generated migration report
 */
export async function generateAndWriteReport(migrationData, outputPath, options = {}) {
  const report = generateMigrationReport(migrationData, options);
  await writeMigrationReport(report, outputPath);
  return report;
}

/**
 * Reads a migration report from a JSON file
 *
 * @param {string} reportPath - Path to report file
 * @returns {Promise<Object>} Migration report object
 */
export async function readMigrationReport(reportPath) {
  if (!await fs.pathExists(reportPath)) {
    throw new Error(`Migration report file not found: ${reportPath}`);
  }

  const content = await fs.readFile(reportPath, 'utf8');
  return JSON.parse(content);
}

/**
 * Creates a migration data object from file operations
 *
 * @param {Object} operations - File operation results
 * @param {Array<Object>} operations.moves - Array of file move results
 * @param {Array<Object>} operations.linkUpdates - Array of link update results
 * @param {Array<Object>} operations.errors - Array of errors
 * @param {Object} operations.validation - Validation results
 * @returns {Object} Migration data object suitable for report generation
 */
export function createMigrationData(operations = {}) {
  const {
    moves = [],
    linkUpdates = [],
    errors = [],
    validation = { passed: true }
  } = operations;

  return {
    movedFiles: moves.map((move) => ({
      source: move.source,
      destination: move.destination,
      status: move.error ? 'failed' : 'success',
      error: move.error || undefined
    })),
    updatedLinks: linkUpdates.map((update) => ({
      file: update.file,
      oldLink: update.oldLink,
      newLink: update.newLink,
      status: update.error ? 'failed' : 'success',
      error: update.error || undefined
    })),
    errors: errors.map((error) => ({
      type: error.type || 'unknown',
      message: error.message,
      file: error.file || undefined,
      details: error.details || undefined
    })),
    validation
  };
}
